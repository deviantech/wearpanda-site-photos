module Traversal
  module ProductDirectoryStructuralConcern

    def verify_structure
      ensure_proper_subdir_structure(entries)
      verify_expected_product_dirs(entries)

      entries.each do |entry|
        check_nested_product_dirs(entry) if ::File.directory?(entry)
        check_directly_publishable_entries_structure(entry) if direct_publish_dir?(entry)
      end
    end

    private

    def validate_has_necessary_photos!
      files = entries('_live')
      App.warn( view('.'), "missing required images: no header found" ) unless files.any? {|f| f =~ /header/ }
      App.warn( view('.'), "missing required images: no editorial found" ) unless files.any? {|f| f =~ /editorial/ }
      App.warn( view('.'), "missing required images: no product photos" ) if files.all? {|f| f =~ /header|editorial/ }
    end

    # Check _publish dirs to ensure matching basenames for any ---upto
    def check_directly_publishable_entries_structure(dir)
      App.dipping_into(dir) do
        entries.each do |entry|
          if entry.match( App::UPTO_REGEX )
            entry_without_upto = entry.gsub(/\s*#{App::UPTO_REGEX}-?\s*/, '')
            unless entries.include?(entry_without_upto)
              raise InvalidStructure, "Publishable #{dir} file with upto is missing non-upto version: #{entry} (checking #{entries} against #{entry_without_upto})"
            end
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
      if (sku_folders = dirs.select {|d| ::File.directory?(d) && !non_sku_subdirs.include?(d) }).length > 0
        App.dipping_into('product') do
          entries.each do |entry|
            next unless entry[0] == '!'
            if sku_folders.length == 1
              puts "WARNING: #{App.dry? ? 'would move' : 'moving'} !-image in product folder to the only SKU folder (#{sku_folders.first}): #{entry}".red
              FileUtils.mv entry, "../#{sku_folders.first}/#{entry}" unless App.dry?
            else
              raise InvalidStructure, "Product has SKUs, so product directory should not contain any '!'-containing filenames (#{view entry})"
            end
          end
        end
      end

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