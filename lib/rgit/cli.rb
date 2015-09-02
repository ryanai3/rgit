
require "thor"

module Rgit
  class Cli < Thor
    desc "test", "A test function"

    def test(*args)
      puts args
    end
  end
end