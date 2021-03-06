Crawler = require("./crawler")
fs = require('fs');

errorfile = "yivo-error.txt"

processYivoPage = (error,result,$) ->
	record = {}
	try

		if (error!=null)
			console.log("#{new Date()}: #{error.message}")
			return null

		# Identifiers (in this case URI and numerical ID)
		record.uri = crawler.prepareURL result.redirect
		try
			record.id = /id=([0-9]+)/g.exec($("#ctl00_placeHolderMain_linkEmailArticle").attr("href"))[1]
		catch error
			console.log("Error (#{record.uri}): #{error.message}")
			fs.appendFile(errorfile, "#{new Date()} Error (#{record.uri}): #{error.message}\n")
			return null

		# Basic stuff
		record.title = $("h1").text()
		record.abstract = $(".articleblockconteiner p").first().text()

		# Images
		record.images = []
		$("img.mbimg").each (index, img) ->
			image = {}
			image.thumbUrl = "http://www.yivoencyclopedia.org#{$(img).attr("src")}"
			image.viewerUrl = /(http.*)&article/g.exec($(img).parent().attr("href"))[1]
			image.imgDesc = $(img).parent().next().text().replace("SEE MEDIA RELATED TO THIS ARTICLE","").trim()
			record.images.push image

		# Links
		record.links = []
		$("#ctl00_placeHolderMain_panelArticleText a[href^='article.aspx/']").each (index,a) ->
			link = {}
			link.href = crawler.prepareURL "http://www.yivoencyclopedia.org/#{$(a).attr("href")}"
			link.text = $(a).text().trim()
			record.links.push link if link.text.length>0 # Strangely, there are sometimes empty links
			crawler.checkForQueue link.href

		# Glossary terms
		record.glossary = []
		$(".term").each (index,span) ->
			term = $(span).text().trim()
			record.glossary.push term if term.length>0  # Strangely, there are sometimes empty spans

		# Subrecords, i.e., multi-page articles (like Poland)
		record.subrecords = []
		isMain =true
		$("#ctl00_placeHolderMain_panelPager a").each (index,a) ->
			sr = {}
			sr.href = crawler.prepareURL "http://www.yivoencyclopedia.org" + $(a).attr("href")
			sr.page = $(a).text().trim()
			if index==0 and sr.href!=record.uri then isMain = false
			if !isMain and index==0
				record.parent = sr.href
				crawler.checkForQueue sr.href
			if isMain and index!=0
				record.subrecords.push sr
				crawler.checkForQueue sr.href

		# Subconcepts, i.e., H2 headings on the same page (not really a concept, but maybe useful)
		record.subconcepts = []
		$("h2.entry").each (index,h2) ->
			sc = $(h2).text().trim()
			if index==0 and !isMain 
				record.title = "#{sc} (#{record.title})"
				return true
			# The following H2 headings are NOT stored as concepts:
			stops = ["About this Article", "Suggested Reading", "YIVO Archival Resources", "Author", "Translation"]
			check = stops.some (word) -> sc==word
			if check
				return false
			record.subconcepts.push sc

		# Next record in alphabet			
		record.next = $("#ctl00_placeHolderMain_linkNextArticle")?.attr("href")
		if record.next!=undefined 
			record.next = "http://www.yivoencyclopedia.org/#{record.next}"
			# console.log("Next: #{record.next}")
			crawler.checkForQueue record.next

		return record
	catch error
		fs.appendFile(errorfile, "#{new Date()} Error (#{record.uri}): #{error.message}\n")
		return null



crawler = new Crawler(processYivoPage)
crawler.outfile = "yivo.json"
crawler.markVisited = (visited, record) ->
	console.log("Yivo visited...")
	visited[record.uri]="http://www.yivoencyclopedia.org/article.aspx?id=#{record.id}"
	visited["http://www.yivoencyclopedia.org/article.aspx?id=#{record.id}"] = record.uri
	visited
crawler.prepareURL = (url) -> 
	url = url.replace(":80", "")
	if url.indexOf("%")>0 then url else encodeURI url
crawler.restart("http://www.yivoencyclopedia.org/article.aspx/Abeles_Shimon")

