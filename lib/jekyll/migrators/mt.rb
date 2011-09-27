# Created by Nick Gerakines, open source and publically available under the
# MIT license. Use this module at your own risk.
# I'm an Erlang/Perl/C++ guy so please forgive my dirty ruby.
 
# Josh Carter mods:
# - Extract categories
# - Add category to post YAML header
# - Create posts under category paths
# - Underbars in post names instead of dashes (specific to my site)
 
require 'rubygems'
require 'sequel'
require 'fileutils'
require 'yaml'
require 'pp'
require 'ostruct'
require 'fileutils'

# NOTE: This converter requires Sequel and the MySQL gems.
# The MySQL gem can be difficult to install on OS X. Once you have MySQL
# installed, running the following commands should work:
# $ sudo gem install sequel
# $ sudo gem install mysql -- --with-mysql-config=/usr/local/mysql/bin/mysql_config

module Jekyll
  module MT
    def self.process(dbname, user, pass, host = 'localhost')
      db = Sequel.mysql(dbname, :user => user, :password => pass, :host => host, :encoding => 'utf8')
      # db = Sequel.sqlite(dbname, :encoding => 'utf8')

      categories = {}
      posts = {}

      #
      # Extract categories
      #
      db["SELECT * FROM mt_category"].each do |c|
        category = OpenStruct.new
        category.category_id = c[:category_id].to_i
        category.name = c[:category_basename]
        category.parent = c[:category_parent].to_i
        
        category.parent = nil if (category.parent == 0)
        
        categories[category.category_id] = category
      end
      
      #
      # Flatten nested categories
      #
      categories.each_value do |c|
        path = [c.name]
        parent_id = c.parent
          
        while parent_id
          parent = categories[parent_id]
          path.unshift parent.name
          parent_id = parent.parent
        end
        
        c.path = path.join '/'
      end

      # puts 'Categories:'
      # categories.keys.sort.each { |k| puts " - #{k} -> #{categories[k].path}" }
      
      db["SELECT * FROM mt_placement"].each do |p|
        next if p[:placement_is_primary].to_i == 0
        
        post = OpenStruct.new
        post.post_id = p[:placement_entry_id]
        post.category_id = p[:placement_category_id]
        post.category = categories[p[:placement_category_id]].path
        
        posts[post.post_id] = post
      end

      # puts 'Posts (after placements):'
      # posts.keys.sort.each { |k| puts " - #{k} -> #{posts[k].category}"}

      db["SELECT * FROM mt_entry"].each do |p|
        post = posts[p[:entry_id]] || OpenStruct.new
        
        post.title = p[:entry_title].to_s
        post.slug = p[:entry_basename].gsub(/_/, '_')
        post.date = p[:entry_authored_on]
        post.content = p[:entry_text]
        
        more_content = p[:entry_text_more]

        # Be sure to include the body and extended body.
        if p[:entry_text_more] != nil
          post.content += "\n"
          post.content += "\n"
          post.content += ":EXTENDED:\n"
          post.content += "\n"
          post.content += p[:entry_text_more]
        end

        # Ideally, this script would determine the post format (markdown,
        # html, etc) and create files with proper extensions. At this point
        # it just assumes that markdown will be acceptable.
        post.name = [post.date.year, post.date.month, 
                     post.date.day, post.slug].join('-') + '.' +
                     self.suffix(p[:entry_convert_breaks])

        post.data = {
           'layout' => 'post',
           'title' => post.title,
           'date' => post.date,
           'category' => post.category
         }.delete_if { |k,v| v.nil? || v == '' }.to_yaml
      end

      # puts 'Posts:'
      # posts.keys.sort.each { |k| puts " - #{k} -> #{posts[k].name} (#{posts[k].category})"}
      
      FileUtils.mkdir_p "_posts"
      posts.keys.sort.each do |post_id|
        post = posts[post_id]
        dir = "_posts/#{post.category}"
        
        FileUtils.mkdir_p(dir)
        
        File.open(File.join(dir, post.name), "w") do |f|
          f.puts post.data
          f.puts "---"
          f.puts post.content
        end
      end
    end

    def self.suffix(entry_type)
      if entry_type.nil? || entry_type.include?("markdown")
        # The markdown plugin I have saves this as
        # "markdown_with_smarty_pants", so I just look for "markdown".
        "markdown"
      elsif entry_type.include?("textile")
        # This is saved as "textile_2" on my installation of MT 5.1.
        "textile"
      elsif entry_type == "0" || entry_type.include?("richtext")
        # Richtext looks to me like it's saved as HTML, so I include it here.
        "html"
      else
        # Other values might need custom work.
        entry_type
      end
    end
  end
end
