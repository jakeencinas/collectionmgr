class TrackMgr {
    [string]$Album
    [string]$Artist
    [string]$AverageBpm
    [string]$BitRate
    [string]$Comments
    [string]$Composer
    [string]$DateAdded
    [string]$DiscNumber
    [string]$Genre
    [string]$Grouping
    [string]$Kind
    [string]$Label
    [string]$Location
    [string]$Mix
    [string]$Name
    [string]$PlayCount
    [string]$Rating
    [string]$Remixer
    [string]$SampleRate
    [string]$Size
    [string]$Tonality
    [string]$TotalTime
    [string]$TrackID
    [string]$TrackNumber
    [string]$Year
    
    #constructors
    TrackMgr(){}

    TrackMgr([pscustomobject]$Track){
        $this.LoadObjectProps($Track)
    }

    #methods
    [void] LoadObjectProps([pscustomobject]$Track){
        foreach($prop in $Track.psobject.Properties){
            if($prop.value.length -gt 0 -and $prop.Name.Contains("@")){
                $propName  = $prop.Name.split("@")[1]
                $this.$propName = $prop.value 
            }
        }
    }

    #static methods
    static [System.IO.FileInfo] GetTrackLocation([TrackMgr]$Track){
        if($Track.Location.Contains("file://localhost")){
            $uri = $Track.Location.split("file://localhost")[1]
            try{
                $trackLocation = Get-Item $([System.Uri]::UnescapeDataString($uri)) -ErrorAction Stop
                return $trackLocation
            }
            catch{
                Write-Error $Error[0]
                Return $null
            }
        }
        else{
            return $null
        }
    }
}

class CollectionMgr {

    [PSCustomObject]$Collection
    [PSCustomObject]$Tracks
    [PSCustomObject]$Playlists
    [PSCustomObject]$Product
    [PSCustomObject]$Version
    
    #Constructors

    CollectionMgr(){}

    CollectionMgr([PSCustomObject]$Import){
        if([CollectionMgr]::ValidateCollection($Import)){
            $this.LoadObjectProps($Import)
        }
        else{
            Write-Error "Could not import collection"
            Return
        }
    }

    CollectionMgr([string]$Path){
        try{
            $data = Get-Content -Path $Path -Raw -ErrorAction Stop 
            $json = $data | ConvertFrom-Json -ErrorAction Stop

            if([CollectionMgr]::ValidateCollection($json)){
                $this.LoadObjectProps($json)
            }
            else{
                Write-Error "Could not import collection"
                Return
            }
        }
        catch{
            Write-Error $Error[0]
            Return 
        }
    }

    #Methods
    [void] LoadObjectProps([pscustomobject]$Import){
        $this.Collection = $Import
        $this.Tracks = $Import.DJ_PLAYLISTS.COLLECTION
        $this.Playlists = $Import.DJ_PLAYLISTS.PLAYLISTS
        $this.Product = $Import.DJ_PLAYLISTS.PRODUCT
        $this.Version = $Import.DJ_PLAYLISTS."@Version"
    }


    #Static Methods
    Static [bool] ValidateCollection([pscustomobject]$Verify){

        $verification = $false
        if($Verify.DJ_PLAYLISTS.COLLECTION.TRACK){
            $verification = $true
        }

        return $verification
    }

    Static [pscustomobject] GetTrackById([string]$TrackId, [CollectionMgr]$Collection){
        $Track = $Collection.Tracks.TRACK | ? {$_."@TrackID" -EQ $TrackId}        
        if($Track.count -gt 0){
            $returnObj = [TrackMgr]::New()
            $returnObj.LoadObjectProps($Track)
            return  $returnObj
        }
        else{
            return $null
        }
    }

    Static [string[]] GetAllPlaylistNames([CollectionMgr]$Collection){
        $list = @()
        foreach($pl in $Collection.Playlists.NODE.NODE) {
            if($pl."@Type" -EQ 1 ){
                $list += $pl."@Name"
            }
        }
        return $list
    }

    Static [TrackMgr[]] GetTracksFromPlaylist([string]$PlaylistName, [CollectionMgr]$Collection){
        $trackObj = @()
        $playlist = $null
        $Collection.Playlists.NODE.NODE | % {
            if($_."@Name" -EQ $PlaylistName){
                $playlist = $_
            }
        }

        if($playlist.TRACK.count -gt 0){
            $idList = @()
            $playlist.TRACK | % {
                $idList += $_."@Key"
            }
            foreach($id in $idList){
                $trackObj += [CollectionMgr]::GetTrackById($id, $Collection)
            }
        }
        return $trackObj
    }

    Static [void] ExportPlaylistToFolder([string]$PlaylistName, [CollectionMgr]$Collection, [System.IO.DirectoryInfo]$Path,[string]$AppendProperty){
        
        #Verify Export Path
        try{
            $ExportPath = Get-Item $Path -ErrorAction Stop
        }
        catch{
            Write-Error $Error[0]
            Return 
        }
        
        [string[]]$testDirectory = $ExportPath.Attributes
        if(!$testDirectory.Contains("Directory")){
            Write-Error "Path must be a valid direcotry"
            Return 
        }

        #Verify valid playlist name
        if(!$([CollectionMgr]::GetAllPlaylistNames($Collection)).Contains($PlaylistName)){
            Write-Error "Could not find playlist: $($PlaylistName)"
            Return
        }

        #verify directory doesn't already exist
        $playlistDirectory = Join-Path $ExportPath.FullName -ChildPath $PlaylistName
        if(!$(Test-Path $playlistDirectory)){
            try{
                New-Item -Path $playlistDirectory -ItemType Directory -ErrorAction Stop
            }
            catch{
                Write-Error "Could not create export directory"
                Write-Error $Error[0]
                return 
            }
        }
        else{
            Write-Error "Directory already exists $($playlistDirectory)"
        }


        #Get tracks
        $trackCollection = [CollectionMgr]::GetTracksFromPlaylist($PlaylistName, $Collection)
        if($trackCollection.count -gt 0){
            foreach ($track in $trackCollection) {
                try{
                    #Get Append data
                    $destination = $null
                    if($null -ne $AppendProperty){
                        if($track.$AppendProperty){
                            $trackName = $([TrackMgr]::GetTrackLocation($track)).Name
                            $append = $track.$AppendProperty
                            if(!$($trackName.StartsWith($append))){
                                $appendedName = $append + "_" + $trackName
                                $destination = Join-Path $playlistDirectory -ChildPath $appendedName
                            }
                            else{
                                $destination = $playlistDirectory
                            }
                        }
                    }
                    else {
                        $destination = $playlistDirectory
                    }

                    Copy-Item -Path $(([TrackMgr]::GetTrackLocation($track)).FullName) -Destination $destination -ErrorAction Stop
                }
                catch{
                    Write-Error "Cannot copy $(([TrackMgr]::GetTrackLocation($track)).FullName)"
                }
            }
        }
        else{
            Write-Error "Could not find tracks from $($PlaylistName)"
        }
    }
}