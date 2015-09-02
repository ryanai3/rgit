module CoreExtensions
  module Pathname
    module EasyChildCheck
      def has_child?(child)
        (self + child).exist?
      end
    end
  end
end

