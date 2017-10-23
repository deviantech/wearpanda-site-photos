module Traversal
  class Directory
    PRODUCT_DIR_DEPTH = 3

    attr_reader :path
    def initialize(path)
      @path = path
    end

    def call
      entries.each do |entry|
        handle_entry(entry)
      end
    end

    private

    def entries
      Dir.entries(path)
    end

    def is_product_directory?(rel_path)
      rel_path.split('/').length == PRODUCT_DIR_DEPTH
    end

    def handle_entry(entry)
      return if entry[0] == '.'

      full_path = ::File.expand_path([path, entry].join('/'))
      rel_path = full_path.sub("#{App.root_dir}/", '')

      if is_product_directory?(rel_path)
        Traversal::ProductDirectory.new(full_path).call
      elsif ::File.directory?(full_path)
        if entry[0] == '_'
          App.log.debug "Skipping underscored directory: #{full_path}".yellow
        else
          Traversal::Directory.new(full_path).call
        end
      else
        App.log.warn "Found unexpected file: #{rel_path}"
      end
    end

  end
end