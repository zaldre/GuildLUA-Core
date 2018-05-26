#Pre-Requisite checks for existing data. Creates directories if they do not exist
$DBSub = $Config.settings.baseconfig.workingdir + '\' + $Config.settings.baseconfig.databasefolder + '\'
$CharacterReportFolder = $RPSub + 'Character\'
$RaidReportFolder = $RPSub + 'Raids\'
if ((test-path $Config.settings.baseconfig.workingdir) -eq $false) { mkdir $Config.settings.baseconfig.workingdir }
if ((test-path $DBSub) -eq $false) { mkdir $DBSub }
if ((test-path $RPSub) -eq $false) { mkdir $RPSub }
$IDLookupPrefix = 'https://classicdb.ch/?item=' #Used in loot output, PREFIX + ITEMID = URL
$joinfile = $dbsub + 'join.csv'
$leavefile = $dbsub + 'leave.csv'
$lootfile = $dbsub + 'loot.csv'
$files = $joinfile, $leavefile, $lootfile

#DB STUFF

#Finding which files are to be used. If no -filename parameter, Search the WoW directory.


#END DB STUFF


#Date/Time in LUA file is always in US format, This variable makes sure we are always able to intepret these entries as datetime objects irrespective of region
$US = New-Object system.globalization.cultureinfo("en-US")

#Checking if we have a blacklist file, If so it is imported.
if (test-path ($Dbsub + 'blacklist.csv')) { $blacklist = import-csv ($DBsub + 'blacklist.csv') }

#Getting the different types of blacklist entries
$BLEvent = $blacklist | Where-Object {$_.type -eq "event"} | Select-Object -ExpandProperty Name
$BLLoot = $blacklist | Where-Object {$_.type -eq "loot"} | Select-Object -ExpandProperty Name
$BLPlayer = $blacklist | Where-Object {$_.type -eq "player"} | Select-Object -ExpandProperty Name


#Functions

#Generate an array full of the loot listings for quicker searching
function genLootArray {
    $script:lootarray = import-csv ($DBSub + '\' + 'loot.csv')
}
function Update-ConfigFile($property, $value) {
    $config.settings. + $property = $value
}
#Function for logging
function Write-Log {
    $currenttime = get-date -Format "[yyyy-MM-dd] H:mm:ss"
    $string = $currenttime + " " + $args
    $string | out-file $Config.settings.baseconfig.logfile -append
    write-host $string
}

Function GenDB {
    param([string]$filename)

    if (!$filename) { 
        "No filename specified. Searching WoW directory for CT_Raidtracker LUA files"
        $WTFAccount = "\WTF\ACCOUNT\"
        try { $DBFilesList = Get-Childitem ($config.settings.baseconfig.wowfolder + $WTFAccount + '\*\SavedVariables\CT_Raidtracker.lua') }
        catch { throw "Error: No files found. Check the wow folder location in the config and try again" ; exit }
        $count = $dbfileslist.count ; "Found $count files"
    }
    else {
        #Sanity check for existence of filename
        $fullpathfilename = (Get-Location).path + '\' + $filename
        if ((test-path $filename) -eq $false) { $Check1 = $false } else { $DBFilesList = Get-ChildItem $filename }
        if ((test-path $fullpathfilename) -eq $false) { $check2 = $false } else { $DBFilesList = Get-ChildItem $fullpathfilename }
        if (($check1 -eq $false) -and ($check2 -eq $false)) {  "ERROR: NO FILE FOUND BY THE NAME OF $filename" ; exit } 
    }
    #Declaring object types
    $player = '				["player"]'
    $time = '				["time"]'
    $name = '					["name"]'
    $colorhex = '					["c"]'
    $count = '					["count"]'
    $ID = '					["id"]'
    $final = '			},'
    $mode = $null
    $int = 0
    
    

    #Declaring objs for holding the data
    $store = @{}

    #Generating database begins
    "Generating database, This may take a few minutes"
    #Beginning loop through files
    $store = foreach ($DBFile in $DBFilesList) {
        $import = Get-Content $Dbfile
        foreach ($entry in $import) { 
            $obj = @()
            $int++ #Counter

            #Determining which block we are processing. Leave, Loot or Join
            if ($entry -eq '		["Leave"] = {') { $mode = "leave"}
            if ($entry -eq '		["Join"] = {') { $mode = "join" }
            if ($entry -eq '		["Loot"] = {') { $mode = "loot" }



            #Parsing individual results
            $Raw = $entry.Split('=')
            $CurrentItem = $Raw[0]
            $Value = $raw[1]
            $value = $value -replace '"', ""
            $value = $value -replace ',', ""


            #Player object begin
            if ($CurrentItem -match [Regex]::Escape($Player)) { 
                $currentPlayer = $raw[1]
                $currentplayer = $currentplayer.Replace('"', '') #Trimming quotation marks
                $currentplayer = $currentplayer.Replace(',', '') #Trimming commas
                $currentplayer = $currentplayer.Trim()           #Trimming whitespace
            }
            #URL processing
            if ($CurrentItem -match [Regex]::Escape($ID)) { 
    
                $URL = $IDLookupPrefix + "$value"
                $url = $url.Replace(" ", "") 
                $Url = $url.Split(':')
                $url = $url[0] + ':' + $url[1]
                #$url
            }

            #Quantity processing
            if ($CurrentItem -match [Regex]::Escape($count)) {  $quantity = $value } #$CurrentItem }

            #Name of items
            if ($CurrentItem -match [Regex]::Escape($name)) { $itemName = $value } #$CurrentItem }

            #Color processing
            if ($CurrentItem -match [Regex]::Escape($colorhex)) {
                $colorvalue = $value.Trim()
                if ($colorvalue -eq "ff9d9d9d") { $coloringame = "Grey" ; $colorpriority = "0"}
                if ($colorvalue -eq "ffffffff") { $coloringame = "White" ; $colorpriority = "1"}
                if ($colorvalue -eq "ff1eff00") { $coloringame = "Green" ; $colorpriority = "2"}
                if ($colorvalue -eq "ff0070dd") { $coloringame = "Blue" ; $colorpriority = "3"}
                if ($colorvalue -eq "ffa335ee") { $coloringame = "Epic" ; $colorpriority = "4" }
                if ($colorvalue -eq "ffff8000") { $coloringame = "Legendary" ; $colorpriority = "5" }
            }


            #Time processing
            if ($CurrentItem -match [Regex]::Escape($time)) {
                if (!$mode) { write-log "Error. Mode unknown on line" $int ; break }

                #Gathering date and time information
                $RawDate = $value -split "\s+"

                #Converting the raw data into a Powershell DATETIME object.
                [datetime]$date = $Rawdate[1] + " " + $rawdate[2]

                #The dates are stored in US format, So let's make sure thats taken into consideration before we start changing things.
                $USFormat = get-date $Date -format ($US.DateTimeFormat.FullDateTimePattern) 
                if ($config.settings.reporting.convServerTime -eq $true) {
                    $ConvertedDate = Convert-DateTime $USformat 
                    $datestamp = get-date $ConvertedDate -format "yyyy.MM.dd"
                    $Timestamp = get-date $ConvertedDate -Format "HH:mm:ss"
                }
        
                else {
                    $datestamp = get-date $USFormat -format "yyyy.MM.dd"
                    $Timestamp = get-date $USformat -Format "HH:mm:ss"
                }
        
            }
            #Conversion finished, Lets now store the date and time in individual variables for ease of access.
    
            #Final block - Write the objects out
            if ($CurrentItem -match [Regex]::Escape($final) -and ($currentitem.length -eq $final.length)) {
                if ($mode -eq "leave") { 
                    $obj = [pscustomobject][ordered]@{
                        Name  = $currentplayer
                        Leave = $timestamp
                        Date  = $datestamp
                        Mode  = $mode
                    }
                    #Passing object to the pipeline to store in $store
                    $obj
                    #Blanking to ensure that data is fresh each loop
                    $obj = $null
                    $currentplayer = $null
                    $timestamp = $null
                }

                if ($mode -eq "join") {
                    $obj = [pscustomobject][ordered]@{
                        Name = $currentplayer
                        Join = $timestamp
                        Date = $datestamp
                        Mode = $mode
                    }
                    #Passing object to the pipeline to store in $store
                    $obj
                    #Blanking to ensure that data is fresh each loop
                    $obj = $null
                    $currentplayer = $null
                    $timestamp = $null
                }

                if ($mode -eq "loot") {
                    $obj = [pscustomobject][ordered]@{
                        Name     = $currentplayer
                        Item     = $itemName.SubString(1)
                        Color    = $colorvalue
                        Quantity = $quantity
                        Quality  = $coloringame
                        Priority = $colorpriority
                        URL      = $URL
                        Date     = $datestamp 
                        Mode     = $mode
                        Loot     = $timestamp
                    }
                    #Passing object to the pipeline to store in $store
                    $obj
                    #Blanking to ensure that data is fresh each loop
                    $obj = $null
                    $currentplayer = $null
                    $itemName = $null
                    $colorvalue = $null
                    $quantity = $null
                    $coloringame = $null
                    $colorpriority = $null
                }
            }
        }

    }
    $joinArr = New-Object System.Collections.ArrayList($null)
    $leaveArr = New-Object System.Collections.ArrayList($null)
    $lootArr = New-Object System.Collections.ArrayList($null)
    foreach ($entry in $store) { 
        switch ($entry.mode) {
            join {[void]$joinArr.Add($entry) }
            leave {[void]$leaveArr.Add($entry)}
            loot {[void]$lootArr.Add($entry)}
        }
    }
    $lootarr | export-csv $lootfile -NoTypeInformation
    $joinarr | export-csv $joinfile -NoTypeInformation
    $leavearr | export-csv $leavefile -NoTypeInformation
    "Database generation complete."
}

function Convert-DateTime($date) {
    $ConvertedDate = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($date, [System.TimeZoneInfo]::Local.Id, $Config.settings.baseconfig.timezoneid)
  return $ConvertedDate
}