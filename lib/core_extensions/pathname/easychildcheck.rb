module CoreExtensions
  module Pathname
    module EasyChildCheck
      def has_child?(child)
        path = self + child
        path.exist? || path.directory?
      end
    end
  end
end

