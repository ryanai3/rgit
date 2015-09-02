#!
require "rgit/version"

class Rgit < Thor
  desc "test", "A test function"
  def test(*args)
    puts args
  end
end

Rgit.start

