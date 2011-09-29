require 'set'
require 'pp'

# Convertible provides methods for converting a pagelike item
# from a certain type of markup into actual content
#
# Requires
#   self.site -> Jekyll::Site
#   self.content
#   self.content=
#   self.data=
#   self.ext=
#   self.output=
module Jekyll
  module Convertible
    # Returns the contents as a String.
    def to_s
      if self.is_a? Jekyll::Post
        (self.content || '') + (self.extended || '')
      else
        self.content || ''
      end
    end

    # Read the YAML frontmatter.
    #
    # base - The String path to the dir containing the file.
    # name - The String filename of the file.
    #
    # Returns nothing.
    def read_yaml(base, name)
      self.content = File.read(File.join(base, name))

      if self.content =~ /^(---\s*\n.*?\n?)^(---\s*$\n?)/m
        self.content = $POSTMATCH
        self.data = {}

        begin
          if self.is_a? Jekyll::Post
            if self.site.config.key? 'post_defaults'
              self.data.merge! self.site.config['post_defaults']
            end
          end

          self.data.merge! YAML.load($1)

          # if we have an extended section, separate that from content
          if self.is_a? Jekyll::Post
            if self.data.key? 'extended'
              marker = self.data['extended']
              self.content, self.extended = self.content.split(marker + "\n", 2)
            end
          end
        rescue => e
          puts "YAML Exception reading #{name}: #{e.message}"
        end
      end

      self.data ||= {}
    end

    # Transform the contents based on the content type.
    #
    # Returns nothing.
    def transform
      
      case self.ext
      when ".textile":
        converter = site.getConverterImpl(Jekyll::TextileConverter)
        self.ext = ".html"
        self.content = converter.convert(self.content)
        if self.is_a? Jekyll::Post and self.extended
          self.extended = converter.convert(self.extended).to_html
        end
      when ".markdown":
        converter = site.getConverterImpl(Jekyll::MarkdownConverter)
        self.ext = ".html"
        self.content = converter.convert(self.content)
        if self.is_a? Jekyll::Post and self.extended
          self.extended = converter.convert(self.extended)
        end
      end
    end

    # Determine the extension depending on content_type.
    #
    # Returns the String extension for the output file.
    #   e.g. ".html" for an HTML output file.
    def output_ext
      converter.output_ext(self.ext)
    end

    # Determine which converter to use based on this convertible's
    # extension.
    #
    # Returns the Converter instance.
    def converter
      @converter ||= self.site.converters.find { |c| c.matches(self.ext) }
    end

    # Add any necessary layouts to this convertible document.
    #
    # payload - The site payload Hash.
    # layouts - A Hash of {"name" => "layout"}.
    #
    # Returns nothing.
    def do_layout(payload, layouts)
      info = { :filters => [Jekyll::Filters], :registers => { :site => self.site } }

      # render and transform content (this becomes the final content of the object)
      payload["pygments_prefix"] = converter.pygments_prefix
      payload["pygments_suffix"] = converter.pygments_suffix

      begin
        self.content = Liquid::Template.parse(self.content).render(payload, info)
      rescue => e
        puts "Liquid Exception: #{e.message} in #{self.name}"
      end

      self.transform

      # output keeps track of what will finally be written
      self.output = self.content

      if self.is_a? Jekyll::Post 
        # make sure we update the payload with transformed data
        payload["page"].merge!({"content" => self.content, "extended" => self.extended})

        if self.extended
          self.output = self.content + self.extended
        end
      end

      # recursively render layouts
      layout = layouts[self.data["layout"]]
      used = Set.new([layout])

      while layout
        payload = payload.deep_merge({"content" => self.output, "page" => layout.data})

        begin
          self.output = Liquid::Template.parse(layout.content).render(payload, info)
        rescue => e
          puts "Liquid Exception: #{e.message} in #{self.data["layout"]}"
        end

        if layout = layouts[layout.data["layout"]]
          if used.include?(layout)
            layout = nil # avoid recursive chain
          else
            used << layout
          end
        end
      end
    end

    # Process scripts for the layout
    #   +scripts+ is a Array of [{"name" => "foo", "command": "foo.py"}]
    #
    # Returns a Hash of {"foo" => "... script output ..."}
    def do_scripts(scripts)
      result = {}
      scripts.each do |script|
        p = IO.popen(File.join(@base, '_scripts', script["command"]) +
                     ' ' + @base)
        result[script["name"]] = p.read || ""
        p.close
      end
      result
    end
  end
end
