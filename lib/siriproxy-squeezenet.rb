require 'cora'
require 'siri_objects'
require 'pp'
require 'socket'
require 'uri'
require 'open-uri'
require 'json'

# SqueezeNet plugin v0.8 by Joep Verhaeg (info@joepverhaeg.nl)
# Last update: Nov 11, 2012
#
# Remember to add this plugin to the "config.yml" file!
######
class SiriProxy::Plugin::SqueezeNet < SiriProxy::Plugin
  def initialize(config)
    # SqueezeServer configuration
    
    # host = config["jb_host"]
    # port = config["jb_port"]
    
    @host = "192.168.1.3"
    @port = 9090
        
    @responses = [ "One moment", "Just a second", "Hold on a second", "Fine", "Give me a second" ]
    @genres = { "alternative" => "1", "black metal" => "2", "blues" => "4", "classical" => "8",
      "country" => "16", "dance" => "32", "death metal" => "64", "electronic" => "128",
      "emo" => "256", "folk" => "512", "hardcore" => "1024", "heavy metal" => "2048",
      "hip-hop" => "4096", "indie" => "8192", "jazz" => "16384", "latin" => "32768",
      "pop" => "65536", "punk" => "131072", "reggae" => "262144", "r&b" => "524288",
      "rock" => "1048576", "singer-songwriter" => "2097152", "soul" => "4194304",
      "trance" => "8388608", "60s" => "16777216", "70s" => "33554432", "80s" => "67108864" }
    @bands = { "full beat" => "volbeat", "a full beat" => "volbeat", "the full beats" => " volbeat",
      "soul fly" => "soulfly", "so fly" => "soulfly" }
  end

  def secondsToTime(seconds)
    mm, ss = seconds.divmod(60)
    hh, mm = mm.divmod(60)
    dd, hh = hh.divmod(24)
    min =  "%d" % [mm]
    sec =  "%d" % [ss]
    if (sec.to_i < 10) then sec = "0#{sec}" end
    return "#{min}:#{sec}"
  end

  def parseResponse(response, command)
    response[command] = "" #replace <macaddr> <command> with nil to remove it
    return response.strip!
  end
  
  def checkShuffleState()
    begin
      socket = TCPSocket.open(@host,@port)
      socket.puts("00:00:00:00:00:00 playlist shuffle ?")
      shuffleStatus = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 playlist shuffle")
      if (shuffleStatus.to_i == 0)
        response = ask "Should I shuffle the current playlist?"
        if(response =~ /yes/i)
          socket.puts("00:00:00:00:00:00 playlist shuffle 1")
          say "Turning shuffle on.", spoken: @responses[rand(@responses.size)]
        else
          say "OK."
        end
      end
      request_completed
    rescue Exception => e
      say e.to_s, spoken: "Uh oh! Something bad happened..."
      request_completed    
    end
  end

  def getCurrentPlaying()
    # 00:00:00:00:00:00 (livingroom)
    # 00:00:00:00:00:00 (bedroom)
    begin
      socket = TCPSocket.open(@host,@port)
      socket.puts("00:00:00:00:00:00 title ?")
      titlePlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 title")
      socket.puts("00:00:00:00:00:00 artist ?")
      artistPlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 artist")
      socket.puts("00:00:00:00:00:00 album ?")
      albumPlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 album")
      socket.puts("00:00:00:00:00:00 duration ?")
      durationPlaying = secondsToTime(parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 duration").to_i)
      socket.puts("00:00:00:00:00:00 playlist index ?")
      indexPlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 playlist index")
      socket.puts("00:00:00:00:00:00 status #{indexPlaying} 1 tags:K")
      status = URI.decode(socket.gets) 
      regex = Regexp.new(/(?<=artwork_url:)(.*)(?=cover.jpg)/)
      artwork_url = regex.match(status)
      if artwork_url
        artworkPlaying = "http://192.168.1.3:9000/#{artwork_url[1]}cover.jpg"
      else
        artworkPlaying = "http://192.168.1.3:9000/music/0/cover.jpg"
      end
      socket.close
      say "You are listening to #{artistPlaying}, playing: #{titlePlaying}, from the album #{albumPlaying}."
      #say "You are listening to #{artistPlaying}, playing: #{titlePlaying}"
      log("Artwork: #{artworkPlaying}")
      object=SiriAddViews.new
      object.make_root(last_ref_id)
      answer=SiriAnswer.new(albumPlaying,[
      SiriAnswerLine.new('no artwork',artworkPlaying),
      SiriAnswerLine.new("Track: #{titlePlaying}"),
      SiriAnswerLine.new("Artist: #{artistPlaying}"),
      SiriAnswerLine.new("Duration: #{durationPlaying}"),
      ])
      object.views << SiriAnswerSnippet.new([answer])
      send_object object
      request_completed
    rescue Exception => e
      say e.to_s, spoken: "Uh oh! Something bad happened..."
      request_completed
    end 
  end

  def findAlbum(spotify_album, spoken_album)
    begin
      # Check ammount of words in album title on Spotify,
      # Because my English is bad, I want for album titles with 1 or 2 words in it a hit if 1,
      # word is the same and for album titles with >3 words in it a hit when 2 words are the same.
      word_count = spotify_album.split.size
      if (word_count < 3) then c = 1 end
      if (word_count >= 3) then c = 2 end
      # Split spoken text into seperate words and check if these words exists in the array 
      # of albums found at Spotify.
      i = 0
      words = spoken_album.split(/ /)
      words.each do |word|
        if spotify_album =~ /#{word}/i
          if (word.downcase != "the") then if (word.downcase != "of") then i+=1 end end
          # puts "found #{i} word of #{c}"
        end
        break if i == c # if word_count is found exit the loop!
      end
      # Return a TRUE if enough words are found, else return FALSE.
      if (i == c) 
        return true
      else
        return false
      end
    rescue Exception => e
      say e.to_s, spoken: "Uh oh! Something bad happened..."
    end
  end

  def playAlbum(album, artist, add)
    begin
      artist = URI.escape(artist.strip)
      results = JSON.parse(open("http://ws.spotify.com/search/1/album.json?q=#{artist}").read)
      if (results["albums"].length > 1)
        albums = results["albums"]
        albums.each do |albumInfo|
          @found = findAlbum(albumInfo["name"], album.strip)
          @foundAlbum = albumInfo["name"]
          @foundURL = albumInfo["href"]
          break if @found == true
        end
         if (@found == true)
           socket = TCPSocket.open(@host,@port)
           if (add == false)
             socket.puts("00:00:00:00:00:00 playlist clear")
           end
           socket.puts("00:00:00:00:00:00 playlist add #{@foundURL}")
           socket.puts("00:00:00:00:00:00 play")
           socket.close
           if (add == false)
             say "You are now listening to #{@foundAlbum}, by #{albums[0]["artists"][0]["name"]}."
           else
             say "Adding the album #{@foundAlbum} to your current playlist."
             checkShuffleState()
           end
         else
           say "I could not find an album called #{album} from the artist #{albums[0]["artists"][0]["name"]}."
         end
      else
       say "I could not find anything by " + URI.decode(artist).titleize + "."
      end
      request_completed
    rescue Exception => e
      say e.to_s, spoken: "Uh oh! Something bad happened..."
      request_completed
    end
  end
  
  def playLatestAlbum (query, add)
    begin
      artist = URI.escape(query.strip)
      results = JSON.parse(open("http://ws.spotify.com/search/1/track.json?q=#{artist}").read)
      if (results["tracks"].length > 1)
        tracks = results["tracks"]
        released = tracks.sort_by { |a| a["album"]["released"] }.reverse!
        socket = TCPSocket.open(@host,@port)
        if (add == false)
          socket.puts("00:00:00:00:00:00 playlist clear")
        end
        socket.puts("00:00:00:00:00:00 playlist add #{released[0]["album"]["href"]}")
        socket.puts("00:00:00:00:00:00 play")
        socket.close
        if (add == false)
          say "You are now listening to #{released[0]["album"]["name"]}, released in #{released[0]["album"]["released"]}."
        else
          say "Adding the album #{released[0]["album"]["name"]} to your current playlist."
          checkShuffleState()
        end
      else
        say "I could not find anything by " + URI.decode(artist).titleize + "."
      end
      request_completed
    rescue Exception => e
      say e.to_s, spoken: "Uh oh! Something bad happened..."
      request_completed
    end
  end

  def playTopTen(query, add)
    begin
      artist = URI.escape(query.strip)
      results = JSON.parse(open("http://ws.spotify.com/search/1/track.json?q=#{artist}").read)
      if (results["tracks"].length > 1)
        tracks = results["tracks"]
        topTen = tracks.sort_by { |a| a["popularity"] }.reverse!
        socket = TCPSocket.open(@host,@port)
        if (add == false)
          socket.puts("00:00:00:00:00:00 playlist clear")
        end
        i = -1
        foundTracks = []
        until (foundTracks.count == 10) do
          i = i +1
          addTrack = true
          foundTracks.each do |trackName|
            if (topTen[i]["name"] == trackName) then addTrack = false end
          end
          if (addTrack == true)
            foundTracks << topTen[i]["name"]
            socket.puts("00:00:00:00:00:00 playlist add #{topTen[i]["href"]}")
          end
        end
        socket.puts("00:00:00:00:00:00 play")
        socket.close
        if (add == false)
          say "Playing #{topTen[0]["artists"][0]["name"]}'s top 10 tracks at Spotify."
        else
          say "Adding #{topTen[0]["artists"][0]["name"]}'s top 10 tracks from Spotify to your current playlist."
          checkShuffleState()
        end
      else
        say "I could not find anything by #{query.titleize}."
      end
      request_completed
    rescue Exception => e
      say e.to_s, spoken: "Uh oh! Something bad happened..."
      request_completed    
    end
  end  
  
  def playSimilarArtists(query)
    begin
      artist = URI.escape(query.strip)
      results = JSON.parse(open("http://ws.spotify.com/search/1/track.json?q=#{artist}").read)
      if (results["tracks"].length > 1)
        uri = open("http://#{@host}:9000/anyurl?p0=spotifyradio&p1=lastfmsimilar&p2=#{artist}&player=00:00:00:00:00:00").read
        say "You are now listening to an artists mix similar to: #{results["tracks"][0]["artists"][0]["name"]}"
      else
        say "I could not find anything by #{query.titleize}."
      end
      request_completed
    rescue Exception => e
      say e.to_s, spoken: "Uh oh! Something bad happened..."
      request_completed
    end
  end
  
  def playArtistMix(query)
    begin
      artist = URI.escape(query.strip)
      results = JSON.parse(open("http://ws.spotify.com/search/1/album.json?q=#{artist}").read)
      if (results["albums"].length > 1)
        artist = results["albums"][0]["artists"][0]["href"]
        uri = open("http://#{@host}:9000/anyurl?p0=spotifyradio&p1=artist&p2=#{results["albums"][0]["artists"][0]["href"]}&player=00:00:00:00:00:00").read
        say "You are now listening to a #{results["albums"][0]["artists"][0]["name"]} mix."
      else
        say "I could not find anything by #{query.titleize}."
      end
      request_completed    
    rescue Exception => e
      say e.to_s, spoken: "Uh oh! Something bad happened..."
      request_completed
    end
  end

  def playRadio(query)
    begin
      if (@genres[query.strip!])
        uri = open("http://192.168.1.3:9000/anyurl?p0=spotifyradio&p1=genre&p2=#{@genres[query]}&player=00:00:00:00:00:00").read
        say "You are now listening to genre radio for '#{query.titleize}'."
      else
        say "There is no radio station for #{query.titleize}"
      end
      request_completed
    rescue Exception => e
      say e.to_s, spoken: "Uh oh! Something bad happened..."
      request_completed
    end
  end

  def getCurrentSongLyrics()
    begin
      socket = TCPSocket.open(@host,@port)
      # Get artist and songtitle...
      socket.puts("00:00:00:00:00:00 title ?")
      titlePlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 title")
      socket.puts("00:00:00:00:00:00 artist ?")
      artistPlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 artist")
      
      # Get lyrics...
      socket.puts("00:00:00:00:00:00 songinfoitems songlyrics")
      songlyrics = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 songinfoitems songlyrics providername:Lyrics delivered by musixmatch.com text:")
      songlyrics["type:text providerlink:http://musixmatch.com count:1"] = "" #remove musixmatch.com footer.
      socket.close

      say "One moment...", spoken: "Here are the lyrics from the track. #{titlePlaying}. by #{artistPlaying}."

      object=SiriAddViews.new
      object.make_root(last_ref_id)
      answer=SiriAnswer.new("#{artistPlaying}: #{titlePlaying}",[
      #SiriAnswerLine.new('no artwork',artworkPlaying),
      SiriAnswerLine.new(songlyrics),
      SiriAnswerLine.new('musixmatch','http://www.joepverhaeg.nl/siri/musixmatch.png'),
      ])
      object.views << SiriAnswerSnippet.new([answer])
      send_object object
      
      request_completed
    rescue Exception => e
      say e.to_s, spoken: "Uh oh! Something bad happened..."
      request_completed
    end
  end
  
  # Check for artist names who Siri does not recognize and correct these...
  def checkUnspeakableArtist(artist)
    artist.strip!.downcase!
    case artist
      when "full beat"
        log "Changed '#{artist}' into Volbeat"
        return "volbeat"
      when "a full beat"
        log "Changed '#{artist}' into Volbeat"
        return "volbeat"
      when "the full beats"
        log "Changed '#{artist}' into Volbeat"
        return "volbeat"
      when "soul fly"
        log "Changed '#{artist}' into Soulfly"
        return "soulfly"
      when "so fly"
        log "Changed '#{artist}' into Soulfly"
        return "soulfly"
      else
        log "Changed nothing for '#{artist}'"
        return artist
    end
  end
  
  # Get current playing song...
  listen_for /(song|track|music).*(playing|hear|hearing|listening)/i do
    getCurrentPlaying()
  end
 
   # Get current playing song lyrics...
  listen_for /(lyrics|text).*(track|song)/i do
    getCurrentSongLyrics()
  end
  
  
  # Add Spotify songs to NEW playlist...
  # Speech examples:
  # say: "listen to Foo Fighters" to play the top 10 tracks by Foo Fighters,
  # say: "listen to music like Michael Jackson" to play a Michael Jackson similar artists mix,
  # say: "listen to the latest Volbeat album" to play a Volbeat's last album,
  # say: "listen to Keep The Faith by Bon Jovi" to play the album Keep The Faith from Bon Jovi.
  # say: "listen to alternative radio" to play Spotify radio with the alternative genre.
  listen_for /(?<=listen to.)(.*)/i do |query|
    say "Searching Spotify...", spoken: ""
    if query =~ /(?<=like.)(.*)/i # check for like in sentence to listen a similar artist mix.
      query.scan(/(?<=like.)(.*)/i) { |q| playSimilarArtists(checkUnspeakableArtist(q[0])) }
    elsif (query =~ /(.*)(?:from|by)(.*)/i) # check for from/by in sentence to detect if an album is wanted.
      query.scan(/(.*)(?:from|by)(.*)/i) { |a, b| playAlbum(a, checkUnspeakableArtist(b), false) }
    elsif (query=~ /(?<=a|an)(.*)top 10/i) # check for a..top 10 in sentence to detect if a top 10 is wanted.
      query.scan(/(?<=to|a|an)(.*)top 10/i) { |q| playTopTen(checkUnspeakableArtist(q[0]), false) }
    elsif (query =~ /(?:newest|latest|last)(.*)(?:record|album|cd)/i) # check for newest/latest album/cd in sentence to detect if the last album is wanted.
      query.scan(/(?:newest|latest|last)(.*)(?:record|album|cd)/i) { |q| playLatestAlbum(checkUnspeakableArtist(q[0]), false) }
    elsif (query =~ /(.*)(?:music|radio)/i) # check for ..radio in sentence to detect if genre radio is wanted.
      query.scan(/(.*)(?:music|radio)/i) { |q| playRadio(q[0]) }
    else
      playArtistMix(checkUnspeakableArtist(query))
    end
  end
  
  # Add Spotify songs to CURRENT playlist...
  # Speech examples:
  # say: "add Foo Fighters" to add the top 10 tracks by Foo Fighters to the current playlist,
  # say: "add Keep The Faith by Bon Jovi" to add the album Keep The Faith from Bon Jovi to the current playlist.
  listen_for /add(.*)/i do |query|
    say "Searching Spotify...", spoken: ""
    if (query =~ /(.*)(?:from|by)(.*)/i) # check for from/by in sentence to detect if an album is wanted.
      query.scan(/(.*)(?:from|by)(.*)/i) { |a, b| playAlbum(a, b, true) }
    elsif (query=~ /(?<=a|an)(.*)top 10/i) # check for a..top 10 in sentence to detect if a top 10 is wanted.
      query.scan(/(?<=to|a|an)(.*)top 10/i) { |q| playTopTen(checkUnspeakableArtist(q[0]), true) }
    elsif (query =~ /(?:newest|latest|last)(.*)(?:record|album|cd)/i) # check for newest/latest album/cd in sentence to detect if the last album is wanted.
      query.scan(/(?:newest|latest|last)(.*)(?:record|album|cd)/i) { |q| playLatestAlbum(q[0], true) }
    else
      playTopTen(query, true)
    end
  end
  
  # Shuffle current playlist on/off
  listen_for /shuffle(?:.*)(on|off|playlist)/i do |command|
    what_to_do = command.downcase
    socket = TCPSocket.open(@host,@port)
    case command
    when "on"
      say "Turning shuffle on."
      socket.puts("00:00:00:00:00:00 playlist shuffle 1")
    when "off"
      say "Turning shuffle off."
      socket.puts("00:00:00:00:00:00 playlist shuffle 0")
    when "playlist"
      say "Turning shuffle on."
      socket.puts("00:00:00:00:00:00 playlist shuffle 1")
    else
      say "What to do with shuffle?"
    end 
  end
  
  # Play/stop/pauze/resume track commands...
  listen_for /(stop|pause|resume).*(?<=music|song|track|playlist)/i do |command|
    what_to_do = command.downcase
    begin
      socket = TCPSocket.open(@host,@port)
      case what_to_do
        when "stop"
          say "Stopping your Squeezebox..."
          socket.puts("00:00:00:00:00:00 stop")
        when "pause"
          say "Pausing your Squeezebox..."
          socket.puts("00:00:00:00:00:00 pause")
        when "resume"
          socket.puts("00:00:00:00:00:00 play")
          say "Resuming your Squeezebox..."  
      end
      socket.close
      request_completed
    rescue
      say "Uh oh! Something bad happened..."
      request_completed
    end
  end
  
  # Next/previous/skip/back track commands...
  listen_for /(next|previous|skip|back).*(song|track)/i do |command|
    what_to_do = command.downcase
    begin
      socket = TCPSocket.open(@host,@port)
      case what_to_do
        when "next"
          socket.puts("00:00:00:00:00:00 playlist index +1")
          dummy = socket.gets
          socket.puts("00:00:00:00:00:00 title ?")
          titlePlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 title")
          socket.puts("00:00:00:00:00:00 artist ?")
          artistPlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 artist")
          say "Skipping to #{artistPlaying}, playing: #{titlePlaying}" 
        when "previous"
          socket.puts("00:00:00:00:00:00 playlist index -1")
          dummy = socket.gets
          socket.puts("00:00:00:00:00:00 title ?")
          titlePlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 title")
          socket.puts("00:00:00:00:00:00 artist ?")
          artistPlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 artist")
          say "Going back to #{artistPlaying}, playing: #{titlePlaying}" 
        when "skip"
          socket.puts("00:00:00:00:00:00 playlist index +1")
          dummy = socket.gets
          socket.puts("00:00:00:00:00:00 title ?")
          titlePlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 title")
          socket.puts("00:00:00:00:00:00 artist ?")
          artistPlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 artist")
          say "Skipping to #{artistPlaying}, playing: #{titlePlaying}" 
        when "back"
          socket.puts("00:00:00:00:00:00 playlist index -1")
          dummy = socket.gets
          socket.puts("00:00:00:00:00:00 title ?")
          titlePlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 title")
          socket.puts("00:00:00:00:00:00 artist ?")
          artistPlaying = parseResponse(URI.decode(socket.gets), "00:00:00:00:00:00 artist")
          say "Going back to #{artistPlaying}, playing: #{titlePlaying}" 
        else
          say "I don't get you."
      end
      socket.close
      request_completed
    rescue Exception => e
      @exception = e.to_s
      say @exception, spoken: "Uh oh! Something bad happened..." 
      request_completed
    end
  end
  
end