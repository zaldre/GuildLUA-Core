PARAM(
    [switch]$db,
    [string]$filename,
)
$ErrorActionPreference = "stop"

$ConfigFile = "H:\GuildLUA\coddddnfig_Lua.xml"


#Making sure an appropriate version of powershell is installed
if ($PSVersionTable.psversion.major -le "4") { 
    'ERROR: Your version of Powershell is out of date and is incompatible with this script.'
    'Please visit https://www.microsoft.com/en-us/download/details.aspx?id=54616 and install Windows Management Framework Version 5 or higher in order to proceed'
    exit 
}

#Configuration file logic.
#First, A static entry can be configured in the "ConfigFile" variable
#If this cannot be located, We look in the current working directory for the file.
#If this can't be found, the script then looks in the script directory
#Failing that, the script will stop.

$currentDir = Get-Location | Select-Object -ExpandProperty path
$scriptLoc = $PSScriptRoot
function Scan-Config {
    param([string]$conf)
    $tempConf = $conf + '\' + 'config_lua.xml'
    if (test-path $tempConf) { 
        write-host "Using configuration file $tempConf"
        [xml]$global:Config = Get-Content $tempCOnf

        #updating the settings if required.
        if ($Config.settings.baseconfig.workingdir -ne $conf) {
            write-host 'Updating the settings to use the current directory as the new working directory'
            $config.settings.baseconfig.workingdir = $conf.ToString()
            $config.save($tempconf)
        }
        return $tempConf
    }
}

#Initial check of config file location
if (!(test-path $configfile)) {
    try {
        $work = Scan-Config -conf $currentDir
        if ($work) { $configfile = $work }
        if ((test-path $configfile) -eq $false) {
            $work = Scan-Config -conf $scriptLoc
            if ($work) { $configfile = $work }
        }
    }
    catch { $error[0] } 
}

#Reloading config file in case there were changes above
[xml]$global:Config = Get-Content $ConfigFile

#Now that the config file is loaded, Let's load the functions module
try {
    #Unloading the existing copy of the module if its loaded - Used in DEV work.
    if (get-module | Where-Object {$_.name -eq "CTRT_Functions"}) { Remove-Module CTRT_Functions }
    Import-Module ($Config.settings.baseconfig.workingdir + '\' + "CTRT_Functions.psm1")
}
catch { 
    throw "ERROR: Unable to load the module 'CTRT_functions.psm1', please ensure this file exists in the working directory"
}


#Update check
$updateFile = $Config.settings.baseconfig.workingdir + '\db\update.csv'
$parent = Split-Path -Path $PSScriptroot -Parent
$version = $PSScriptroot.Split('\')[-1]
$file = $parent + "\Updater.ps1" + " -version $version"
if (!(test-path $updatefile)) {
    &$file
}
else {
    $daysBetween = New-Timespan -end (Get-Date) -start (get-date (Import-Csv $updateFile | Select-Object -ExpandProperty Date))
    if ($daysBetween.days -ge 7) { &$file }
}

#FLAGS SECTION START

if (($filename) -and (!$db)) { throw "Error: Filename parameter is used to specify an individual LUA file to populate the database. Only use this flag in conjunction with -db"}

if ($db) {
    #Calling GenDB Function
    if ($filename) { GenDB -filename $filename }
    else { GenDB }
} 
