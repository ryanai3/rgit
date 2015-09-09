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
        init_subrepo(subrepo_parent, git_parent, directory)
      else
        init_repo(directory, options)
      end
    end

    desc "test", "A test function"
    def test(*args)
      puts args
    end
  end
end

module Impl

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
    start_dir.ascend { |dir|
      if dir.has_child? ".git"
        res_dir = dir
        break
      end
    }
    res_dir
  end

  def lowest_gitrepo_above(start_dir)
    res_dir = nil
    start_dir.ascend{ |dir|
      if dir.has_child? ".git"
        res_dir = dir
        break
      end
    }
  end

  def lowest_above(start_dir)
    lowest_gitrepo = lowest_gitrepo_above(start_dir)
    lowest_subrepo = Branches.new(lowest_gitrepo).branch_for_path(start_dir)
    [lowest_subrepo || lowest_gitrepo, lowest_gitrepo]
  end

  # Calling git & shells
  def git_command(cmd, opt_str, dir)
    run_in_shell("git #{cmd} #{opt_str}", dir)
  end

  def run_in_shell(cmd, dir)
    `cd #{dir}; #{cmd}`
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
  def uncap_cap!(dir)
    branches = Branches.new(dir)
    group_head = branches.current_group
    git_command("reset", "--hard HEAD~1", dir)
    yield group_head
    opt_str = ""
    branches[group_head].each{|branch| opt_str << branch.full_name << " "}
    git_command("merge", opt_str, dir)
  end

  def uncap_cap(dir)
    stash_unstash(dir) do
      uncap_cap!(dir)
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

  def initial_repo_setup_in(directory, branch = "@master/./master")
    # 1. Add a fake original commit so that we can graft once and for all
    #    and a fake first commit to have the original as its parent
    # Add a first commit in master branch
    git_command("checkout", branch, directory)
    git_command("commit", "--allow-empty -m \"first commit in #{directory}\"", directory)
    first_commit = git_command("log", "--format=%H -n1", directory).strip
    # Add a first commit in base branch for grafts
    git_command("checkout", "--orphan @rgit-base-for-graft", directory)
    git_command("commit", "--allow-empty -m \"original in #{directory}\"", directory)
    orig_commit = git_command("log", "--format=%H -n1", directory).strip
    # Return git to requested branch
    git_command("checkout", branch, directory)
    
    # 2. Add a graft so we have a fake "first commit" for all subrepos
    # that we can use for cthulhu merges :)
    Grafts.append_to_grafts!(directory, first_commit, orig_commit)
  end

  class Branches
    attr_accessor :current_group
    def initialize(dir)
      @groups = self.get_branches(dir)
      @dir = dir
      @current_group = git_command("symbolic-ref", "HEAD", dir)
                           .strip.gsub("ref/heads/", "")
    end

    def update
      @groups = self.get_branches(@dir)
      @current_group = git_command("symbolic-ref", "HEAD", @dir)
                           .strip.gsub("refs/heads/", "")
    end

    def self.get_branches(dir)
      heads = dir + ".git/refs/heads"
      groups = heads.children(false).select do |path|
        path.to_s.start_with?("@")
      end
      groups.map{|group| [group, extract_branches(group)]}.to_h
    end

    def self.extract_branches(path)
      res = {}
      path.children.each do |child|
        name = child.basename.to_str
        if name.start_with?("&")
          res[:sitting_branch] = child
        else
          res[name] = extract_branches(child)
        end
      end
      res
    end

    def groups
      @groups.keys
    end

    def branch_for_path(path)
      branch = nil
      so_far = @groups[@current_group]
      path.relative_path_from(@dir).descend do |f|
        sitting_branch = so_far[:sitting_branch]
        branch = sitting_branch if sitting_branch
        so_far = so_far[f]
      end
    end
  end

  class Grafts < Hash
    def self.from_git(directory)
      @location = directory + ".git/info/grafts"
      res = new
      @location.open.readlines.each do |line|
        # Shas are 40 characters, first sha is child
        # TODO: HANDLE GRAFT FILES W/ MORE THAN ONE FAKE PARENT FOR A COMMIT
        res.store(*line.gsub(" ", "").slice(40))
      end
      res
    end

    def self.append_to_grafts!(directory, child_sha, parent_sha)
      graft_dir = directory + ".git/info"
      FileUtils.mkdir_p(graft_dir)
      File.open(graft_dir + "grafts", "w") { |file|
        file.puts "#{child_sha} #{parent_sha}"
      }
    end

    def write_to_disk!
      FileUtils.mkdir_p(@location.dirname)
      File.open(@location, 'w') do |f|
        each do |k, v|
          f << "#{k} #{v}\n"
        end
      end
    end
  end
end
