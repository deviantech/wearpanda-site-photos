module Photos
  class Editorial < Base

    def expected_w_to_h
      # 0.618
      1.5
    end

    def min_height
      800
    end

    def min_width
      nil
    end

  end
end