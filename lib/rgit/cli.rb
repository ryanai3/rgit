require 'byebug'
# stdlib imports
require "pathname"
# gem imports
require "thor"
require "rugged"
require "parseconfig"
# Local imports
require_relative "descriptions"
require_relative "version"

# Monkey Patches - import
require "core_extensions/pathname/easychildcheck.rb"
# Monkey Patches - apply
Pathname.include CoreExtensions::Pathname::EasyChildCheck

module Impl

end

module Wrappers
  class Branches
    include Impl
    attr_accessor :current_group, :current_branch
    def initialize(dir)
      @groups = get_branches(dir)
      @dir = dir
      update
      @groups2branch = flat_hash(@groups).each.select { |k, v|

      }

    end

    def update
      @groups = self.get_branches(@dir)
      @current_branch = git_command("symbolic-ref", "HEAD", @dir)
                            .strip.gsub("refs/heads/", "")
      @current_group = @current_branch[1..-1].split("/", 2)[0]
    end

    def flat_hash(h,f=[],g={})
      return g.update({ f=>h }) unless h.is_a? Hash
      h.each { |k,r| flat_hash(r,f+[k],g) }
      g
    end

    def get_branches(dir)
      self.class.get_branches(dir)
    end

    def self.get_branches(dir)
      heads = dir + ".git/refs/heads"
      groups = heads.children.select do |path|
        path.basename.to_s.start_with?("@")
      end
      # remove first char("@") from group, extract branches
      groups.map{|group| [group.basename.to_s[1..-1], extract_branches(group)]}.to_h
    end

    def extract_branches(path)
      self.class.extract_branches(path)
    end

    def self.extract_branches(path)
      res = {}
      if path.directory?
        path.children.each do |child|
          name = child.basename.to_s
          if name.start_with?("%")
            res[:sitting_branch] = child.to_s.split(".git/refs/heads/", 2)[1]
          else
            res[name] = extract_branches(child)
          end
        end
      end
      res
    end

    def groups
      @groups.keys
    end

    def [](group)
      structure = @groups[group]
      flat_hash(structure).values
    end

    def branch_for_path(path)
      branch = nil
      so_far = @groups[@current_group]
      path.realpath.relative_path_from(@dir).descend do |f|
        file_str = f.basename.to_s
        sitting_branch = so_far[:sitting_branch]
        branch = sitting_branch if sitting_branch
        so_far = so_far[file_str]
      end
      branch
    end

    def path_for_branch(branch_fullname)
      # branchname is a fully qualified path from top git repo
      # + other info
      # i.e. #{group}/full/path/to/#{sub_branch}
      # unless it's a group-level branch in which case
      # #{group}/%group
      group, branch = branch_fullname.split("/", 2)
      path = branch.rpartition("%")[0]
      @dir + path
    end
  end

  class Grafts
    attr_accessor :location
    def initialize(location)
      @location = location
      @grafts = {}
    end

    def [](key)
      @grafts[key]
    end

    def []=(key, value)
      @grafts[key] = value
    end

    def self.from_git(directory)
      location = directory + ".git/info/grafts"
      res = new(location)
      location.open.readlines.each do |line|
        # Shas are 40 characters, first sha is child
        # TODO: HANDLE GRAFT FILES W/ MORE THAN ONE FAKE PARENT FOR A COMMIT
        key, value = line.gsub(" ", "").scan(/.{40}/)
        res[key] = value
      end
      res
    end

    def self.append_to_grafts!(directory, child_sha, parent_sha)
      graft_dir = directory + ".git/info"
      FileUtils.mkdir_p(graft_dir)

      if (graft_dir + "grafts").exist?
        grafts = from_git(directory)
        grafts[child_sha] = parent_sha
        grafts.write_to_disk!
      else
        File.open(graft_dir + "grafts", "w") { |file|
          file.puts "#{child_sha} #{parent_sha}"
        }
      end
    end

    def self.graft_to_base!(directory, child_sha)
      parent_sha = File.open(
          directory + ".git/refs/heads/@rgit-base-for-graft",
          &:readline).strip
      append_to_grafts!(directory, child_sha, parent_sha)
    end

    def write_to_disk!
      FileUtils.mkdir_p(@location.dirname)
      File.open(@location, 'w') do |f|
        @grafts.each do |k, v|
          f << "#{k} #{v}\n"
        end
      end
    end
  end

  #contains the info for a subrepo from the perspective of the parent
  # i.e. what is put in the ".gitmodules" file
  class Submodules
    include Impl
    def initialize(path:)
      @path = path
      @conf = begin
        ParseConfig.new(@path + ".gitmodules")
      rescue Errno::EACCES
        File.open(@path + ".gitmodules", "w") { |f| f.puts("") }
        ParseConfig.new(@path + ".gitmodules")
      end

      submodules = @conf.get_groups.select { |n| n.start_with?("submodule") }
      @submodules = submodules.map { |name|
        v = @conf[name]
        k = name.sub("submodule ", "").gsub(/"/, "")
        [k, v]
      }.to_h
    end

    def add(name: "", values: {})
      @conf.add("submodule \"#{name}\"", values)
    end

    def write_to_disk!
      File.open(@path + ".gitmodules", "w") { |f| @conf.write(f, false)}
    end
  end

  # contains the info for a subrepo necessary for operations stored in
  # it's ".subrepo" file (version controlled by parent)
  class SubRepoInfo
    include Impl
    attr_accessor :pin, :rgit_version
    def initialize(pin:, rgit_version: VERSION, dir:)
      @pin = pin
      @rgit_version = rgit_version
      @loc = dir + ".subrepo"
    end

    def self.default(dir)
      self.new(
          pin: "latest",
          rgit_version: VERSION,
          dir: dir,
      )
    end

    def write_to_disk!
      File.open(@loc, "w") do |f|
        f.puts("pin = #{@pin}\n"\
              "rgit_version = #{@rgit_version}")
      end
    end
  end
end

module Rgit
  class Cli < Thor
    include Impl
    descriptions = Descriptions.new
    @init_descriptions = descriptions.init

    desc "init", "Create an empty Rgit repository or reinitialize an existing one"
    long_desc @init_descriptions[:long_desc]
    method_option :quiet,
      { aliases: "q",
        type: :boolean,
        default: false,
        desc: @init_descriptions[:quiet]
      }
    method_option :bare,
      { type: :boolean,
        default: false,
        desc: @init_descriptions[:bare]
      }
    method_option :template,
      { type: :string,
        desc: @init_descriptions[:template]
      }
    method_option :separate_git_dir,
      { type: :string,
        desc: @init_descriptions[:separate_git_dir]
      }
    method_option :shared,
      { type: :string,
        enum: ["false", "true", "umask", "group", "all", "world", "everybody"],
        desc: @init_descriptions[:shared]
      }
    def init(directory = Pathname.pwd)
      # Get directory as pathname, default being current location
      directory = Pathname.new(directory)
      unless directory.exist? # make the directory if it doesn't exist
        directory.mkpath
      end

      # Find parent subrepo/repo if it exists
      git_parent, subrepo_parent = lowest_above(directory)
      # If we have a parent, and that parent is not us
      # -> initialize a subrepo
      # else -> initialize a repo
      # dir != parent check is needed since user may "re-init" a repo
      if (git_parent) && directory != git_parent
        init_subrepo(git_parent, subrepo_parent, directory)
      else
        init_repo(directory, options)
      end
    end

    desc "test", "A test function"
    def test(*args)
      j = args.class
    end
  end
end

module Impl
  VERSION = Rgit::VERSION
  include Wrappers
  require "pty"
  def format_options(option_hash)
    result = ""
    option_hash.each { |k, v|
      key_str = " --#{k.to_s.gsub("_", "-")}"
      case v # v is truthy in all cases except: nil, false
        when [true, false].include?(v) # it's a boolean
          result << key_str
        when String
          result << key_str << "=#{v}"
        when Fixnum
          result << key_str << "=#{v}"
        when Hash
          v.each { |key, val|
            result << key_str << " #{key}=#{val}"
          }
      end
    }
    result
  end

  def lowest_repo_above(start_dir)
    res_dir = nil
    start_dir.realpath.ascend { |dir|
      if dir.has_child? ".git"
        res_dir = dir
        break
      end
    }
    res_dir
  end

  def lowest_gitrepo_above(start_dir)
    res_dir = nil
    start_dir.realpath.ascend{ |dir|
      if dir.has_child? ".git"
        res_dir = dir
        break
      end
    }
    res_dir
  end

  def lowest_above(start_dir)
    lowest_gitrepo = lowest_gitrepo_above(start_dir)
    lowest_subrepo = nil
    if lowest_gitrepo
      branches = Branches.new(lowest_gitrepo)
      lowest_subrepo = branches.path_for_branch(branches.branch_for_path(start_dir))
    end
    [lowest_gitrepo, lowest_subrepo]
  end

  # Calling git & shells
  def git_command(cmd, opt_str, dir)
    run_in_shell("git #{cmd} #{opt_str}", dir)
  end

  def run_in_shell(cmd, dir)
    output = `cd #{dir}; #{cmd}; cd; cd - ;`
    output
  end

  # Opens a virtual shell at the specified
  # dir and runs the given cmd
  def run_in_pty(cmd, dir)
    result = ''
    PTY.spawn("cd #{dir.realpath}; #{cmd}") do |stdout, stdin, pid|
      begin
        stdout.each { |line| result += line }
      rescue Errno::EIO #Done getting output
        result
      end
    end
    result
  end

  # Transactions
  def stash_unstash(dir)
    git_command("stash", "", dir)
    yield
    git_command("stash", "pop --index", dir)
  end

  # git branch inside is the top branch of the group we were just in
  def uncap_cap!(git_dir)
    # grab info we need to restore state, and remove the cap
    branches = Branches.new(git_dir)
    group_head = branches.current_group
    current_branch = branches.current_branch
    git_command("reset", "--hard HEAD~1", git_dir)
    yield branches # give block the branches object so it knows where it is
    branches.update
    opt_str = ""
    branches[group_head].each{|branch| opt_str << branch << " "}
    git_command("checkout", current_branch, git_dir) #back to prev branch
    git_command("merge", opt_str, git_dir) # merge 'em in!
  end

  def init_subrepo(git_dir, parent_dir, subrepo_dir)
    stash_unstash(git_dir) do
      uncap_cap!(git_dir) do |branches|

        # 1. a) Create .subrepo file in subrepo dir, creating subrepo dir if it's not there
        #    b) Add entry to parent's .submodules file
        parent_branch = branches.branch_for_path(subrepo_dir)
        git_command("checkout", parent_branch, git_dir)

        FileUtils.mkdir_p(subrepo_dir)
        sub_relative = subrepo_dir.realpath.relative_path_from(parent_dir)
        group = branches.current_group
        submodule_info = Submodules.new(path: parent_dir)
        submodule_info.add(
            name: subrepo_dir.basename.to_s,
            values: {path: sub_relative,
                     branch: group}
        )
        SubRepoInfo.default(subrepo_dir).write_to_disk!
        submodule_info.write_to_disk!

        # 2. Add it to parent branch - we're on @group/path/to/parent/branch so we can just
        # add & commit simply
        git_command("add", ".", git_dir)
        git_command("commit", "-m \"Initialized subrepo #{sub_relative}\"", git_dir)
        # 3. Create a branch for the subrepo, and graft it to the base
        branch_name = "#{parent_branch.rpartition("%")[0]}#{sub_relative}/%#{group}"
        create_and_graft_orphan(git_dir, branch_name)
        # return back to parnt
        git_command("checkout", parent_branch, git_dir)
      end
    end
  end

  def init_repo(directory, options)
    repo_already_exists = directory.has_child?(".git")
    # 1. Initialize a git repository w/ provided options
    git_command("init", format_options(options), directory)
    initial_repo_setup_in directory unless repo_already_exists
    puts("Initialized empty rGit repository in #{directory}") unless options[:quiet]
  end

  def do_first_commit_in(
      directory,
      branch,
      message = "first commit in #{directory}"
  )
    git_command("checkout --orphan", branch, directory)
    `cd #{directory}; git rm -rf .`
    git_command("commit", "--allow-empty -m \"#{message}\"", directory)
    File.open(
        directory + ".git/refs/heads/#{branch}",
        &:readline).strip
  end

  def create_and_graft_orphan(
      git_dir,
      branch_name,
      message = "first commit for #{branch_name}"
  )
    git_command("checkout", "--orphan #{branch_name}", git_dir)
    # `git rm --cached . -rf`
    # `git commit --allow-empty -m #{message}`
    # `git add . ; git add . ; git add .`
    # `git rm -rf .`
    #

    git_command("rm", "-rf .", git_dir)
    git_command("commit", "--allow-empty -m \"#{message}\"", git_dir)
    first_commit = File.open(
        git_dir + ".git/refs/heads/#{branch_name}",
        &:readline
    ).strip
    Grafts.graft_to_base!(git_dir, first_commit)
  end

  def initial_repo_setup_in(directory, branch = "@master/%master")
    # 1. Add a fake original commit so that we can graft once and for all
    #    and a fake first commit to have the original as its parent
    # Add a first commit in master branch
    first_commit = do_first_commit_in(directory, branch)
    # Add a first commit in base branch for grafts
    do_first_commit_in(
        directory,
        "@rgit-base-for-graft",
        "original in #{directory}"
    )
    # Return git to requested branch
    git_command("checkout", branch, directory)
    
    # 2. Add a graft so we have a fake "first commit" for all subrepos
    # that we can use for cthulhu merges :)
    Grafts.graft_to_base!(directory, first_commit)
    # add the cap commit
    git_command("commit", "--allow-empty -m \"CAP_COMMIT\"", directory)
  end
  # All the information needed for rgit operations about a subrepo/repo
  class RepoInfo
    attr_accessor :subrepo_info, :submodule_info, :subrepos
    def self.initialize(subrepo_info:, submodule_info:, subrepos: [])
      @subrepo_info = subrepo_info
      @submodule_info = submodule_info
      @subrepos = subrepos
    end

    # def self.default(path)
    # new(
    #     path: path,
    #     url: nil,
    #     branch: "master",
    #     pin: "latest",
    #     subrepos: [],
    #     is_head: true,
    # )
    # end

    def self.build_from(dir)
      values = ParseConfig.new(@path + ".gitmodules")
      # values = File.open(dir + ".subrepo").readlines.map do |line|
      #   line.gsub(/.*=/, "").strip
      # end

      values.each_slice(4).map do |args|
        new(*args, dir)
      end
    end

    def write_to_disk!
      ParseConfig.new(@path + ".gitmodules")


      # File.open(@loc, "w") { |f|
      #   f.put("[subrepo]\n"\
      #         "\tremote = #{@remote}\n"\
      #         "\tbranch = #{@branch}\n"\
      #         "\tpin = #{@pin}\n"\
      #         "\trgit_version = #{@rgit_version}"
      #   )
      # }
      @loc # for easy & fast chaining - i.e. index << write_to_disk!
    end
  end
end
