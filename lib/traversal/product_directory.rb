module Traversal
  class ProductDirectory
    include ProductDirectoryStructuralConcern

    attr_reader :path
    def initialize(path)
      @path = path
    end

    def product_id
      ::File.basename(path).split(' - ').last
    end

    def call
      App.dipping_into(path) do
        verify_structure

        case App.action
        when :rename then rename_photos
        when :select then select_photos
        when :validate then validate_photos
        when :publish then publish_photos
        else raise "Unknown action: #{App.action}"
        end
      end
    rescue InvalidStructure => e
      puts e.message.send(:red)
      exit
    end

    private

    def rename_photos
      entries.each do |dir|
        next if dir == '_live'

        App.dipping_into(dir) do
          rename_files_in('.')
        end
      end
    end

    def select_photos
      clear_live_folder!

      entries.each do |dir|
        next if dir == '_live'
        App.dipping_into(dir) do
          move_skus_to_live(publish_all: direct_publish_dir?(dir))
        end
      end
    end

    def validate_photos
      validate_has_necessary_photos!

      App.dipping_into('_live') do
        entries.each do |entry|
          photo = Photos.for_path(entry)
          photo.process
        end

        unless App.dry?
          App.optim.optimize_images( entries ) do |unoptimized, optimized|
            next unless optimized
            App.log.debug "[Optimize] #{unoptimized} => #{optimized}"
          end
        end
      end
    end

    def publish_photos
      App.sync_api.sync_product_up(self)
    end

    def clear_live_folder!
      return if App.dry?
      FileUtils.rm_rf('_live')
      FileUtils.mkdir('_live')
    end

    def direct_publish_dir?(dir)
      %w(_editorials _headers).include?(dir)
    end

    def rename_files_in(dir)
      bang_i, normal_i = [1, 1]

      sorted_entries(dir).each do |entry|
        old_path = ::File.expand_path(entry)
        (new_idx, new_path) = Traversal::File.new(old_path, entry[0] == '!' ? bang_i : normal_i).local_path
        entry[0] == '!' ? (bang_i = new_idx) : (normal_i = new_idx)

        unless old_path == new_path
          puts "#{App.dry? ? 'Would rename' : 'Renaming'}: #{view(old_path)} -> #{view(new_path)}".yellow
          raise(InvalidStructure,"Trying to rename from non-existant source: #{view old_path}") unless ::File.exists?(old_path)
          raise(InvalidStructure,"Trying to overwrite file: #{view new_path}") if ::File.exists?(new_path)

          ::File.rename(old_path, new_path) unless App.dry?
        end
      end
    end

    def move_skus_to_live(publish_all:)
      idx = 0
      sorted_entries.each do |entry|
        next unless publish_all || entry[0] == '!'

        old_path = ::File.expand_path(entry)
        idx += 1
        live_name = Traversal::File.new(old_path, idx).live_name

        App.log.info App.dry? ? "Would mark for publishing: #{entry} -> #{live_name}" : "Marked for publishing: #{live_name}".cyan
        ::FileUtils.cp(old_path, "../_live/#{live_name}") unless App.dry?
      end
    end

    def sorted_entries(dir = '.')
      parent_dir = ::File.expand_path(dir).split('/')[-1].sub(/^_/, '').sub(/s$/, '')
      subdirs = entries(dir).select do |entry|
        if ::File.directory?(entry)
          App.log.debug "Skipping nested folder: #{entry}".yellow
          nil
        elsif Traversal::IMG_EXTENSIONS.include?( ::File.extname(entry) )
          true
        else
          App.log.debug "Skipping unhandled extension for: #{entry}".yellow
          nil
        end
      end

      subdirs.sort do |a,b|
        ia = idx_from_path(a)
        ib = idx_from_path(b)
        if ia && ib
          ia <=> ib
        elsif ia || ib
          ia ? -1 : 1
        else
          a <=> b
        end
      end
    end

    def idx_from_path(p)
      if matched = p.sub(App::UPTO_REGEX, '').match(/.+[-\s](\d+)\./)
        matched[1].to_i
      end
    end

    def entries(dir = '.')
      Dir.entries(dir).select {|p| p[0] != '.' }
    end

    def view(path)
      path = ::File.expand_path(path)
      path.sub(App.root_dir + '/', '')
    end

  end
end