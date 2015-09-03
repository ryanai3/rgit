# stdlib imports
require "pathname"
# gem imports
require "thor"
# Local imports
require_relative "descriptions"
# Monkey Patches - import
require "core_extensions/pathname/easychildcheck.rb"
# Monkey Patches - apply
Pathname.include CoreExtensions::Pathname::EasyChildCheck


module Rgit
  class Cli < Thor

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
    def init

    end

    desc "test", "A test function"
    def test(*args)
      puts args
    end
  end
end

module Impl
  class Cli
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

    def git_command(cmd, opt_str, dir)
      capture_pty_stdout("git #{cmd} #{opt_str}", dir)
    end

    # Opens a virtual shell at the specified
    # dir and runs the given cmd
    def capture_pty_stdout(cmd, dir)
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


    def init_subrepo(parent_dir, subrepo_dir)

    end

    def init_repo(directory, options)
      # Check if a git repository exists.
      already_has_git = directory.has_child?(".git")
      # 1. Initialize a git repository w/ provided options
      git_command("init", format_options(options), directory)

      puts("Initialized empty rGit repository in #{directory}") unless options[:quiet]
    end

    def initial_repo_setup_in(directory)
      # 1. Add a fake original commit so that we can graft once and for all
      #    and a fake first commit to have the original as its parent

      # Add a first commit in master branch
      git_command("commit", "--allow-empty -m \"first commit in #{directory}\"", directory)
      first_commit = git_command("log", "--format=%H -n1", directory).strip
      # Add a first commit in base branch for grafts
      git_command("checkout", "--orphan @rgit-base-for-graft", directory)
      git_command("commit", "--allow-empty -m \"original in #{directory}\"", directory)
      orig_commit = git_command("log", "--format=%H -n1", directory).strip
      # Return git to master branch
      git_command("checkout", "master")
    
      # 2. Add a graft so we have a fake "first commit" for all subrepos
      # that we can use for cthulhu merges :)
      Grafts.append_to_grafts!(directory, first_commit, orig_commit)
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

Rgit.include Impl # for non-cli methods

