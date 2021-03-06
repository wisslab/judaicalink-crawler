http = require('http')
cheerio = require('cheerio')
fs = require('fs');
path = require('path');


class Crawler
	
	constructor: (@processPage, @markVisited) ->
		@visited = {} # Map of visited URLs (Needed as we have two URLs per page, ?id= and /title)
		@counter = 0
		@running = 0
		@queued = 0
		@queue = []
		@working = []
		@records = []
		@running = 0
		@lastRequest = 0
		@githash = githash()
		@outfile = "output.json"
		@errorfile = "error.txt"
		@prepareURL = (url) -> url
		if (@markVisited==undefined)
			@markVisited = (visited, record) ->
				visited[record.uri] = ""

		@maxSockets = 5
		@requestDelay = 300
		http.globalAgent.maxSockets = @maxSockets

	restart: (@seed) ->
		# Load previous results, if not yet finished
		try
			output = fs.readFileSync(@outfile)
			@records = JSON.parse(output)
		catch error
			if error.code!="ENOENT" 
				try
					@records = JSON.parse(output + "]")
				catch error2
					console.log error2.message
					return
		@counter = @records.length

		# Recreate the map of visited URLs
		for r in @records
			@markVisited(@visited, r)

		# Queue all link from pages that we already visited
		for r in @records
			if r.links
				for l in r.links
					@checkForQueue l.href

		console.log("Queued URLs: " + @queued)
		console.log("Records loaded: #{@records.length}")
		console.log("Visited: #{Object.keys(@visited).length}")

		if @counter==0
			fs.writeFile(@outfile, "[\n")

		# Queue Index page anyway to get all pages
		@checkForQueue @seed

		# Log start time
		console.log(new Date())

	# Helper function that only queues a URL if we haven't visited it yet.
	checkForQueue: (url, priority=false) ->
		url = @prepareURL (url)
		if @visited[url]==undefined and @queue.indexOf(url)<0 and @working.indexOf(url)<0
			# console.log("Queued: " + url + " Encoded: " + encodeURI(url))
			if priority then @queue.unshift(url) else @queue.push(url)
			console.log("Queued: #{url} (Queue size: #{@queue.length})")
			@queued++
			@processQueue()
			return

	request: (url, callback, redirect, trace) ->
		# console.log "request #{url}, redirect: #{redirect}"
		if redirect==undefined
			@running++
			redirect = url
			trace = []
			trace.push(url)
		else
			trace.push(redirect)
		doRequest = () =>
			now = new Date().getTime()
			if (now-@lastRequest<@requestDelay)
				setTimeout(doRequest, now-@lastRequest)
				return
			console.log("Request: #{now} (#{now-@lastRequest})")
			@lastRequest = now
			req = http.get redirect, (res) =>
				console.log "Resonse: #{res.statusCode} (#{new Date().getTime()-now} ms)"
				if res.statusCode>=300 and res.statusCode < 307
					@request(url, callback, res.headers["location"], trace)
					res.on "data", ->
					return
				if res.statusCode!=200
					e = new Error("Server Error: #{res.statusCode}, URL: #{url}, Requested: #{redirect}")
					e.url = url
					res.redirect = redirect
					res.trace = trace
					console.log("Trace: " + trace.join("->"))
					callback(e)
					res.on "data", ->
					@requestComplete(url)
					return
				html = ""
				res.on "data", (chunk) =>
					# console.log "Chunk"
					html += chunk
				res.on "end", =>
					if (@visited[url]) != undefined # visited in the meantime
						@requestComplete(url)
						return
					# console.log "No more data"
					# console.log "Preparing response: html=#{html}, res.data=#{res.data}" 
					res.data = html if (res.data==undefined)
					# console.log "Preparing response: url=#{url}, res.url=#{res.url}" 
					res.url = url
					res.redirect = redirect
					res.trace = trace
					console.log("Trace: " + trace.join("->"))
					record = callback(null, res, cheerio.load(html))
					if record!=null
						record.trace = trace.join("->")
						record.created = new Date().toISOString()
						record.githash = @githash
						@records.push record
						fs.appendFile(@outfile, (if @counter++>0 then ",\n" else "") + JSON.stringify(record,null,1))	
						# Mark as visited
						trace.forEach((u)=>@visited[u]="")
						@markVisited(@visited, record)
						console.log("#{@counter}. Processed #{record.uri} (id=#{record.id}) (R/Q/Q=#{@running}/#{@queued}/#{@queue.length}) (#{new Date().getTime()-now} ms)")
					@requestComplete(url)
			req.on "error", (e) =>
				e.url = url
				callback(e)
				@requestComplete(url)
		doRequest()

	requestComplete: (url) ->
		@running--
		@queued--
		index = @working.indexOf(url)
		@working.splice(index, 1) if (index > -1) 
		if (@running==0) then @processQueue()

	processQueue: ->
		# console.log "Checking queue: #{@queue.length}, Running: #{@running}"
		if (@queue.length==0 and @running==0)
			@finish()
			return

		if (@running<@maxSockets)
			toProcess = @queue.splice(0,@maxSockets)
			@working = @working.concat(toProcess)
			for q in toProcess
				@request(q,@processPage)
			# console.log("New crawling started with queue size #{toProcess.length} (Queue: #{queue.length})")
		return 


	# When finished, close the array in the output file
	finish: ->
		fs.appendFile(@outfile, "]\n")
		console.log("Finished: " + new Date())



gitdir = ->
	path.join(require("parentpath").sync(".git"),".git")

gitref = ->
	fs.readFileSync(path.join(gitdir(),"HEAD"), "utf8").replace("ref: ", "").trim()

githash = -> fs.readFileSync(path.join(gitdir(),gitref()), "utf8").trim()


module.exports = Crawler