require 'digest'

module Traversal
  class File

    attr_reader :full_path, :path, :entry, :idx
    def initialize(path, idx)
      @full_path = path
      @path = ::File.dirname path
      @entry = ::File.basename path
      @idx = idx
      raise(RuntimeError, ":idx argument is required") unless idx.to_i > 0
    end

    def local_path(use_idx: true, use_hash: false)
      suffix = [use_idx ? idx : nil, maybe_upto, ext_name].join

      [
        # If we have an upto present, don't increment the index
        has_upto? ? idx : (idx + 1),
        generate_name(
          use_hash ?
            [maybe_bang, file_hash, use_idx ? " #{idx}" : nil, maybe_upto, ext_name].compact.join :
            [maybe_bang, middle_name(local: true), suffix].compact.join(' ')
        )
      ]
    end

    def live_name
      ::File.basename generate_name(
        name_base,
        transformed_part('category'),
        transformed_part('product'),
        middle_name,
        [idx, maybe_upto, ext_name].compact.join
      )
    end

    private

    def ext_name
      ::File.extname(entry)
    end

    def generate_name(*name_parts, divider: '-')
      newname = name_parts.compact.join(divider)
      newname = newname.gsub('_-', '_').gsub('-_', '_').gsub(/-{4,}/, '---')

      "#{path}/#{newname}"
    end

    def name_base
      'panda-bamboo'
    end

    def maybe_bang
      return '!' if entry[0] == '!'
    end

    def has_upto?
      !! maybe_upto
    end

    def maybe_upto
      if matched = entry.match(/(#{App::UPTO_REGEX})/)
        matched[1]
      end
    end

    def transformed_part(part)
      base = parts[part]
      if part == 'product'
        base = base.sub(/ - \d{9,20}$/, '')
        base = base.sub(/ultralight/, '')
        base = base.sub(/rx/, '')
      end

      base.downcase.strip.gsub(/\s/, '_')
    end

    def middle_name(local: false)
      case parts['sku']
      when /header/ then 'header'
      when /editorial/ then 'editorial'
      else
        sku = transformed_sku( parts['sku'] )
        local ? sku : "__#{sku}__"
      end
    end

    # Take off the size, e.g. for Traveler
    def transformed_sku(sku)
      sku.sub(/-(s|l)$/i, '')
    end

    def file_hash
      Digest::MD5.hexdigest( ::File.read(full_path) )
    end

    PATH_PART_LABELS = ['sku', 'product', 'category']

    def path_parts
      path_parts ||= path.split('/').reverse
    end

    def parts
      @parts ||= PATH_PART_LABELS.zip(path_parts).to_h
    end

  end
end