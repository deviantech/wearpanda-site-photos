module Traversal
  class ProductDirectory
    include ProductDirectoryStructuralConcern

    attr_reader :path
    def initialize(path)
      @path = path
    end

    def product_dir_name
      ::File.basename(path)
    end

    def product_id
      product_dir_name.split(' - ').last
    end

    def call
      App.dipping_into(path) do
        verify_structure

        case App.action
        when :rename then rename_photos
        when :prepare then prepare_photos
        when :publish then publish_photos
        when :block then instance_eval(&App.block)
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

      verify_post_renaming
    end

    def prepare_photos
      clear_live_folder! if App.reprocess_all_files?
      prep_live_folder

      wanted = select_live_photos

      App.dipping_into('_live') do
        existing_hashes = App.image_hashes_for(entries, product_name: path)
        process_and_move_live_photos!(wanted)
        remove_unwanted_photos!(existing_hashes.keys, wanted.keys)
      end

      validate_has_necessary_photos!
    end

    def with_tempfile_path(path, &block)
      temp = Tempfile.new
      begin
        temp.write( ::File.read(path) )
        temp.rewind

        block.call(temp.path)
      ensure
        temp.close
        temp.unlink
      end
    end

    def process_and_move_live_photos!(wanted)
      prev_wanted = read_processed_file_meta

      wanted.keys.each do |live_name|
        data = wanted[live_name]
        prev = prev_wanted[live_name]

        if prev && prev['source'] == data['source'] && prev['source_md5'] == data['source_md5'] && ::File.exists?(live_name)
          App.log.debug "No changes to #{live_name}"
        else
          with_tempfile_path(data['source']) do |tmp_path|
            photo = Photos.for_path( tmp_path, name: live_name, source_path: data['source'] )
            App.dry? ? photo.validate! : photo.process!

            App.log.info "#{App.dry? ? 'Would mark' : 'marked'} #{prev ? 'changed' : 'new'} image for publishing: #{live_name}"
            ::FileUtils.cp(tmp_path, live_name) unless App.dry?
          end
        end
      end

      write_processed_file_meta(wanted)
    end

    def write_processed_file_meta(meta)
      ::File.write('.meta', JSON.dump(meta))
    end

    def read_processed_file_meta
      JSON.parse( ::File.read('.meta') )
    rescue
      {}
    end

    def select_live_photos
      entries.each_with_object({}) do |dir, hash|
        next if dir == '_live'
        App.dipping_into(dir) do
          hash.merge! select_skus_for_live(publish_all: direct_publish_dir?(dir))
        end
      end
    end

    def remove_unwanted_photos!(existing, touched)
      untouched_files = existing - touched
      return if untouched_files.blank?

      App.log.info "#{App.dry? ? 'Would remove' : 'Removing'} #{untouched_files.length} unwanted previously-live image#{untouched_files.length == 1 ? '' : 's'}"

      untouched_files.each do |filename|
        App.log.debug "\t- #{App.dry? ? 'Would remove' : 'Removing'} #{filename}"
        ::File.unlink(filename) unless App.dry?
      end
    end

    def clear_live_folder!
      if App.dry?
        App.log.warn "Skipping reprocessing all files while in dry mode -- validations may not be run on the correct final files"
      else
        FileUtils.rm_rf('_live')
        FileUtils.mkdir('_live')
      end
    end

    def publish_photos
      App.sync_api.sync_product_up(self)
    end

    def prep_live_folder
      FileUtils.mkdir('_live') unless ::File.exists?('_live')
    end

    def direct_publish_dir?(dir)
      %w(_editorials _headers).include?(dir)
    end

    def rename_files_in(dir)
      bang_i, normal_i = [1, 1]

      uptos, normal = sorted_entries(dir)
      normal.each do |entry|
        old_path = ::File.expand_path(entry)
        (new_idx, new_path) = Traversal::File.new(old_path, entry[0] == '!' ? bang_i : normal_i).local_path

        rename_file(old_path, new_path)

        # Give any uptos the same basename as their source file
        any_uptos(uptos, entry) do |upto_path|
          (_, new_upto_path) = Traversal::File.new(upto_path, entry[0] == '!' ? bang_i : normal_i).local_path
          rename_file(upto_path, new_upto_path)
        end

        entry[0] == '!' ? (bang_i = new_idx) : (normal_i = new_idx)
      end
    end

    def any_uptos(uptos, file, &block)
      uptos.select {|u| u.sub(App::UPTO_REGEX, '') == file}.each do |upto|
        upto_path = ::File.expand_path(upto)
        block.call(upto_path)
      end
    end

    def rename_file(old_path, new_path)
      return if old_path == new_path
      puts "#{App.dry? ? 'Would rename' : 'Renaming'}: #{view(old_path)} -> #{view(new_path)}".yellow
      raise(InvalidStructure,"Trying to rename from non-existant source: #{view old_path}") unless ::File.exists?(old_path)
      raise(InvalidStructure,"Trying to overwrite file: #{view new_path}") if ::File.exists?(new_path)

      ::File.rename(old_path, new_path) unless App.dry?
    end

    def select_skus_for_live(publish_all:)
      idx = 0

      uptos, normal = sorted_entries
      wanted = normal.select { |f| publish_all || f[0] == '!' }.each_with_object({}) do |entry, hash|
        idx += 1
        source_path = ::File.expand_path(entry)
        live_name = Traversal::File.new(source_path, idx).live_name

        hash[live_name] = {
          'source' => source_path,
          'source_md5' => App.file_hash(source_path),
        }

        # Also bring over any uptos, forcing the same IDX name as their source
        any_uptos(uptos, entry) do |upto_path|
          upto_live_name = Traversal::File.new(upto_path, idx).live_name
          hash[upto_live_name] = {
            'source' => upto_path,
            'source_md5' => App.file_hash(upto_path),
          }
        end
      end
    end

    def sorted_entries(dir = '.')
      parent_dir = ::File.expand_path(dir).split('/')[-1].sub(/^_/, '').sub(/s$/, '')
      subdirs = entries(dir).select do |entry|
        if ::File.directory?(entry)
          App.log.debug "Skipping nested folder: #{entry}".yellow
          nil
        elsif Traversal::IMG_EXTENSIONS.include?( ::File.extname(entry).downcase )
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
      end.partition {|e| e =~ App::UPTO_REGEX }
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