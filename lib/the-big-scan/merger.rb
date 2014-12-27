require 'fileutils'
require 'highline/import'
require 'pdf-reader'
require 'tempfile'

class Merger
  def initialize(document, directory, overwrite, cleanup, show_commands)
    @document = document
    @directory = directory

    full_path = File.join(@directory, @document)
    if File.exists?(full_path)
      if overwrite
        say "<%= color('Deleting: #{full_path}', RED) %>"
        FileUtils.rm_f full_path
      else
        say "<%= color('That document already exists!: #{@document}', RED) %>"
        exit 1
      end
    end

    @show_commands = show_commands
    @cleanup = cleanup
  end

  def merge!(documents, include_existing)
    Dir.chdir(@directory) do
      say("<%= color('In directory \"#{@directory}\"', GREEN) %>") if @show_commannds

      pdfs_to_merge = if include_existing
                        Dir.glob('*.pdf').sort
                      else
                        documents.sort
                      end
      page_counts = [1]

      pdfs_to_merge.each do |pdf_file|
        page_counts << (page_counts[-1] + PDF::Reader.new(pdf_file).page_count)
      end

      config = Tempfile.new('ghostscript-config')
      begin
        pdfs_to_merge.each_with_index do |pdf_file, i|
          config.write "[/Title (#{pdf_file.gsub(/\.pdf$/, '')}) /Page #{page_counts[i]} /OUT pdfmark\n"
        end
        config.close

        pdf_files = pdfs_to_merge.map {|p| "'#{p}'"}
        cmd = "ghostscript -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite '-sOutputFile=#{@document}' #{pdf_files.join(' ')} #{config.path}"
        say("<%= color(\"#{cmd}\", BLUE) %>") if @show_commands

        system cmd
        if $? != 0
          say "<%= color('Unable to merge pdfs!', RED) %>"
          exit 1
        end
      ensure
        config.unlink
      end

      if @cleanup
        pdfs_to_merge.each {|file| FileUtils.rm_f(file)}
      end
    end
  end
end
