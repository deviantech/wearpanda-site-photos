module Traversal
  module ProductDirectoryStructuralConcern

    def verify_structure
      ensure_proper_subdir_structure(entries)
      verify_expected_product_dirs(entries)

      entries.each do |entry|
        check_nested_product_dirs(entry) if ::File.directory?(entry)
      end
    end

    def verify_post_renaming
      entries.each do |entry|
        check_directly_publishable_entries_structure(entry) if direct_publish_dir?(entry)
        check_sku_dir_has_selected_image(entry) unless non_sku_subdirs.include?(entry)
      end
    end

    private

    def no_header_needed?
      path.include?('xmas-shop')
    end

    def validate_has_necessary_photos!
      files = entries('_live')
      App.warn( view('.'), "missing required images: no header found" ) unless files.any? {|f| f =~ /header/ } || no_header_needed?
      App.warn( view('.'), "missing required images: no editorial found" ) unless files.any? {|f| f =~ /editorial/ }
      App.warn( view('.'), "missing required images: no product photos" ) if files.all? {|f| f =~ /header|editorial/ }

      files.each do |file|
        next unless missing_upto_match?(file, files)
        raise InvalidStructure, "[#{product_dir_name}] _live file with upto is missing non-upto version: #{file} \n(checking #{files})"
      end
    end

    def missing_upto_match?(file, files)
      return unless file.match( App::UPTO_REGEX )
      file_without_upto = file.sub(/\s*#{App::UPTO_REGEX}\s*/, '')
      ! files.include?(file_without_upto)
    end

    def check_sku_dir_has_selected_image(dir)
      App.dipping_into(dir) do
        next if entries.any? {|e| e[0] == '!' }
        App.warn product_dir_name, "#{dir} has no images selected for publishing"
      end
    end

    # Check _publish dirs to ensure matching basenames for any ---upto
    def check_directly_publishable_entries_structure(dir)
      App.dipping_into(dir) do
        entries.each do |entry|
          if missing_upto_match?(entry, entries)
            raise InvalidStructure, "[#{product_dir_name}] Publishable #{dir} file with upto is missing non-upto version: #{entry} \n(checking #{entries})"
          end
        end
      end
    end

    def ensure_proper_subdir_structure(dirs)
      non_sku_subdirs.each do |d|
        FileUtils.mkdir(d) unless dirs.include?(d)
      end
    end

    def non_sku_subdirs
      %w(_headers _editorials _live product)
    end

    def verify_expected_product_dirs(dirs)
      dirs.each do |entry|
        next if non_sku_subdirs.include?(entry)

        if ::File.directory?(entry)
          unless entry == entry.upcase
            raise InvalidStructure, "Unexpected product folder '#{view entry}': SKU folders expected to be in all caps"
          end
        else
          if sku_folders.length > 0
            raise InvalidStructure, "Found file where expecting only folders: #{view entry}. File in one of the SKU folders (#{sku_folders})."
          else
            raise InvalidStructure, "Found file where expecting only folders: #{view entry}. For products without SKUs, put the product photos the folder called 'product'"
          end
        end
      end
    end

    def check_nested_product_dirs(entry)
      nested = entries(entry)
      unwanted_dirs = nested.select {|d| ::File.directory?("#{entry}/#{d}") }

      if unwanted_dirs.length > 0
        raise InvalidStructure, "Unexpected nested directories in #{path}/#{entry}: #{unwanted_dirs}"
      end
    end

  end
end