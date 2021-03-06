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
            [maybe_bang, middle_name(standalone: true), suffix].compact.join(' ')
        )
      ]
    end

    # NOTE: Shopify appears to only consider the first (eh... ~30-36) characters of the filename when determining
    # whether or not they think it's a duplicate (and should get the name mangled with a GUID), so we need to put the unique
    # parts of the name near the beginning.
    def live_name
      [
        transformed_part('product'),
        middle_name(standalone: false), # Will have word dividers on either side
        idx,
        maybe_upto,
        '-',
        parts['sku'] =~ /editorial/ && bang? ? 'square-' : nil,
        [name_base, ext_name].join
      ].compact.join
    end

    def file_hash
      Digest::MD5.hexdigest( ::File.read(full_path) )
    end

    private

    def ext_name
      ::File.extname(entry).downcase
    end

    def generate_name(*name_parts, divider: '-')
      newname = name_parts.compact.join(divider)
      newname = newname.gsub('_-', '_').gsub('-_', '_').gsub(/-{4,}/, '---')

      "#{path}/#{newname}"
    end

    def name_base
      base = transformed_part('category')
      case base
      when 'panda'      then 'wearpanda'
      when 'xmas-shop'  then "panda-#{base}"
      else "panda-bamboo-#{base}"
      end
    end

    def bang?
      entry[0] == '!'
    end

    def maybe_bang
      return '!' if bang?
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
        base = base.sub(/rx.*/, '')
      end

      base.downcase.strip.gsub(/\s/, '_').gsub(/[^-_\d\w]/, '-')
    end

    def middle_name(standalone:)
      case parts['sku']
      when /header/ then standalone ? 'header' : "__header__"
      when /editorial/ then standalone ? 'editorial' : "__editorial__"
      else
        sku = transformed_sku( parts['sku'] )
        standalone ? sku : "___#{sku}___"
      end
    end

    # Take off the size, e.g. for Traveler
    def transformed_sku(sku)
      sku.sub(/-(s|l)$/i, '')
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