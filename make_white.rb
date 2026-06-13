require 'chunky_png'

src_dir = 'assets/fonts'
dst_dir = 'assets/fonts/white'
Dir.mkdir(dst_dir) unless Dir.exist?(dst_dir)

(1..80).each do |num|
  src = format("#{src_dir}/symbol%03d.png", num)
  dst = format("#{dst_dir}/symbol%03d.png", num)
  next unless File.exist?(src)

  img = ChunkyPNG::Image.from_file(src)
  img.height.times do |y|
    img.width.times do |x|
      pixel = img[x, y]
      r = ChunkyPNG::Color.r(pixel)
      g = ChunkyPNG::Color.g(pixel)
      b = ChunkyPNG::Color.b(pixel)
      a = ChunkyPNG::Color.a(pixel)
      if r == 0 && g == 0 && b == 0
        img[x, y] = ChunkyPNG::Color.rgba(255, 255, 255, a)
      end
    end
  end
  img.save(dst)
  puts "Whitened #{src} -> #{dst}"
end