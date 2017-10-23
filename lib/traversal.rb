require_relative 'traversal/directory'
require_relative 'traversal/product_directory_structural_concern'
require_relative 'traversal/product_directory'
require_relative 'traversal/file'

module Traversal
  IMG_EXTENSIONS = %w(.jpg .jpeg .tiff)

  def self.call(root_path)
    Traversal::Directory.new(root_path).call
  end
end