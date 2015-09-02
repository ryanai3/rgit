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
    no_commands {
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
    }

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