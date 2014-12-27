require 'highline/import'
require 'time'
require 'sane'

class GeneratorUI
  # TODO: Pass more options to the scanner
  def initialize(options)
    @document = if options[:document] =~ /\.pdf$/
                  options[:document]
                else
                  "#{options[:document]}.pdf"
                end
    @directory = options[:Directory]
    FileUtils.mkdir_p(@directory) unless Dir.exists?(@directory)
    @include_existing = options[:'include-existing']
    @cleanup = options[:cleanup]
    @show_commands = options[:'Show-commands']
    @preview = options[:preview]
    @viewer = options[:viewer]
    @overwrite = options[:overwrite]

    @scanner = Sane.open {|sane| sane.devices[0].name}

    @year = nil
    @month = nil
    @day = nil
    @title = nil

    @run = true
  end

  def run!
    documents = []

    while @run
      ask_year
      ask_month
      ask_day
      ask_title

      # Scan the document
      say("Generating '#{current_document_name}'")
      Scanner.new(scanner: @scanner,
                  Directory: @directory,
                  document: current_document_name,
                  resolution: 300,
                  :'Show-commands' => @show_commands,
                  :'Page-size' => "letter",
                  :'no-cleanup' => false,
                  preview: true,
                  viewer: @viewer).scan!
      documents << current_document_name

      choose do |menu|
        menu.prompt = "What would you like to do? "

        menu.choice(:finish) { @run = false }
        menu.choice(:redo) { FileUtils.rm_f(File.join(@directory, "#{current_document_name}.pdf"))}
        menu.choice(:add)
      end
    end

    # Merge documents
    say("Merging documents into: #{@directory}/#{@document}")
    merger = Merger.new(@document, @directory, @overwrite, @cleanup, @show_commands)
    merger.merge!(documents, @include_existing)

    if @preview && !Kernel.fork
      Dir.chdir(@directory)
      Kernel.exec("#{@viewer} '#{@document}' > /dev/null 2>&1 &")
    end
  end

  private
  def current_document_name
    "%i.%02i.%02i - %s.pdf" % [@year, @month, @day, @title]
  end

  def ask_year
    @year = ask("What year is the document? ",
                Integer) {|q| q.default = @year; q.in = 1900..(Time.now.year)}
  end

  def ask_month
    @month = ask("What month is the document? ",
                 Integer) {|q| q.default = @month; q.in = 1..12}
  end

  def ask_day
    @day = ask("What day is the document? ",
               Integer) {|q| q.default = @day; q.in = 1..31}
  end

  def ask_title
    @title = ask("What is the document title? ",
                 String) {|q| q.default = @title; q.validate = /.+/}
  end
end
