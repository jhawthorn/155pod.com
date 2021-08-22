
require "uri"
require "net/http"
require "feedjira"
require "nokogiri"
require "active_support/all"

class Post
  attr_accessor :prev, :next
  attr_reader :entry

  def initialize(entry)
    @entry = entry
  end

  def date
    entry.published
  end

  def title
    entry.title
  end

  def path
    "#{entry.published.strftime("%F")}-#{entry.title.parameterize}.html"
  end

  def to_html
    doc = Nokogiri::HTML(entry.content)

    link = doc.at('a[href*="covers."]')
    remove_node_and_parents(link.parent)

    link = doc.at('a:contains("View this email in your browser")')
    remove_node_and_parents(link)

    preheader = +""
    preheader << %{<a href="/newsletter" style="display: block;">1:55 Newsletter Archive</a>}
    preheader << %{<a href="#{prev.path}" style="display: block;">&laquo; Previous: #{prev.title}</a>} if prev
    preheader << %{<a href="#{self.next.path}" style="display: block">&raquo; Next: #{self.next.title}</a>} if self.next
    doc.at('#templatePreheader').inner_html = preheader

    cta = doc.at('em:contains("1:55 is a weekly newsletter for Patreon Gatekeepers.")')
    cta.inner_html = %{1:55 is a weekly newsletter for <a href="https://www.patreon.com/155pod">Patreon Gatekeepers</a>.}

    logo = doc.at(".mcnImage")
    logo["alt"] = "1:55"
    link = doc.create_element "a"
    logo.replace(link)
    link["href"] = "https://155pod.com"
    link.inner_html = logo

    meta = doc.at('meta[name="viewport"]')
    meta_info.each do |name, content|
      meta.add_next_sibling(%{<meta name="#{name}" content="#{content}">})
    end

    doc.to_html
  end

  private

  def meta_info
    {
      "twitter:card" => "summary",
      "twitter:site" => "@155pod",
      "twitter:title" => "1:55",
      "twitter:image" => "https://155pod.com/newsletter_logo.png",
      "twitter:description" => "#{title} - 1:55 - A newsletter about a podcast about &ldquo;punk&rdquo; songs."
    }
  end

  def remove_node_and_parents(node)
    node_to_remove = node
    while node_to_remove.inner_html.strip == node.inner_html.strip
      node_to_remove = node_to_remove.parent
    end
    node_to_remove.remove
  end
end

url = ENV.fetch("NEWSLETTER_FEED")
uri = URI.parse(url)
response = Net::HTTP.get_response(uri)
xml = response.body

feed = Feedjira.parse(xml)
posts = feed.entries.map { |entry| Post.new(entry) }
posts.reverse!
posts.each_cons(2) { |p, n| p.next = n; n.prev = p }

index_template = ERB.new(<<ERB)
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<meta charset="UTF-8">
<title>1:55 - A newsletter about a podcast about "punk songs."</title>
<style>
      body {
        font-family: Helvetica, Verdana, sans-serif;
        text-align: center;
      }

      a, a:visited {
        color: blue;
        text-decoration: none;
      }

      ul {
        list-style: none;
      }

      ul li {
        padding-top: 1.5em;
      }

</style>
<meta name="twitter:card" content="summary">
<meta name="twitter:site" content="@155pod">
<meta name="twitter:title" content="1:55">
<meta name="twitter:image" content="https://155pod.com/newsletter_logo.png">
<meta name="twitter:description" content="1:55 - A newsletter about a podcast about &ldquo;punk&rdquo; songs. By @samsthrlnd and @josiahhughes.">
</head>
<body>
<h1>1:55 Newsletter</h1>
<ul>
<% posts.reverse_each do |post| %>
  <li>
    <a href="/newsletter/<%= post.path %>">
      <%= post.date.strftime("%B %d") %><br/><%= post.title %>
    </a>
  </li>
<% end %>
</ul>
</body>
</html>
ERB

posts.each do |post|
  html = post.to_html
  puts post.path
  File.write("newsletter/#{post.path}", html)
end

index_html = index_template.result(binding)
puts "index.html"
File.write("newsletter/index.html", index_html)
