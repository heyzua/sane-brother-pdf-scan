require 'fileutils'
require 'highline/import'
require 'digest'
require 'open3'

class Scanner
  INCHES_IN_MILLIMETER = 0.0393007874

  def initialize(options)
    @scanner = options[:scanner]
    @directory = options[:Directory]
    FileUtils.mkdir_p(@directory) unless Dir.exists?(@directory)
    @document = if options[:document] =~ /\.pdf$/
                  options[:document]
                else
                  "#{options[:document]}.pdf"
                end
    @hash = Digest::SHA1.hexdigest(@document)
    @resolution = "%i" % options[:resolution]

    case options[:'Page-size']
    when /^letter$/ then
      @page_width  = "%.1f" % (8.48 / INCHES_IN_MILLIMETER)
      @page_height = "%.1f" % (11.0 / INCHES_IN_MILLIMETER)
    when /^legal$/ then
      @page_width  = "%.1f" % (8.48 / INCHES_IN_MILLIMETER)
      @page_height = "%.1f" % (14.0 / INCHES_IN_MILLIMETER)
    end

    @cleanup = !options[:'no-cleanup']
    @preview = options[:preview]
    @viewer = options[:viewer]
    @show_commands = options[:'Show-commands']
  end

  def scan!
    Dir.chdir(@directory) do
      say("<%= color('In directory \"#{@directory}\"', GREEN) %>") if @show_commands

      # TODO: Only works on new Brother scanners
      scanimage = "scanimage --device-name='#{@scanner}' --format tiff --batch='#{@hash}-%d.tif' --source 'Automatic Document Feeder(centrally aligned)' --mode 'Gray' --resolution #{@resolution} -y #{@page_height} -x #{@page_width}"
      execute(scanimage, "Unable to scan document.") do |line|
        if line =~ /^(Scanned page \d*\.)/
          $stdout.write "#{$1}\r"
          $stdout.flush
        end
      end
      $stdout.write "\n"

      tiffs = Dir.glob("#{@hash}-*.tif").sort do |a, b|
        page_number(a) <=> page_number(b)
      end

      final_tiff = "#{@hash}-complete.tif"

      tiffcp = "tiffcp -c g4 #{tiffs.join(' ')} #{final_tiff}"
      execute(tiffcp, "Unable to merge tiff files.")

      tiff2pdf = "tiff2pdf -c '#{@document.gsub(/\.pdf$/, '')}' -j -o '#{@document}' #{final_tiff}"
      execute(tiff2pdf, "Unable to generate PDF from TIFF file.")

      if @cleanup
        tiffs.each {|file| FileUtils.rm_f(file)}
        FileUtils.rm_f final_tiff
      end

      if @preview && !Kernel.fork
        Kernel.exec("#{@viewer} '#{@document}' > /dev/null 2>&1 &")
      end
    end
  end

  private
  def execute(cmd, msg, &block)
    say("<%= color(\"#{cmd}\", BLUE) %>") if @show_commands
    exitcode = nil
    Open3.popen2e(cmd) do |stdin, stdout, wait|
      stdout.each do |line|
        yield line if block_given?
      end
      exitcode = wait.value
    end

    if !exitcode.success? && (cmd !~ /^scanimage/ && exitcode.exitstatus != 7)
      say("<%= color('#{msg} (#{$?})', RED) %>")
      exit 1
    end
  end

  def page_number(file)
    file.scan(/.*?-(\d*)\.tif/).flatten[0].to_i
  end
end
