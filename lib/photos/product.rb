module Photos
  class Product < Base

    def min_width
      source_path =~ /xmas-shop/ ? 380 : 960
    end

    def min_height
      source_path =~ /xmas-shop/ ? 380 : 625
    end
  end
end