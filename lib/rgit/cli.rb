
require "thor"

module Rgit
  class Cli < Thor
    descriptions = Descriptions.new
    @init_descriptions = descriptions.init

    desc "init", "Create an empty Rgit repository or reinitialize an existing one"
    def init

    end

    desc "test", "A test function"
    def test(*args)
      puts args
    end
  end
end