#Requires -Modules Corkscrew,UniversalDashboard

$ApiName = "updaterule"

$RootDirectory = Split-Path -Path $MyInvocation.MyCommand.Path

$Endpoint = New-UDEndpoint -Url "/$ApiName" -Method "POST" -ArgumentList $RootDirectory -Endpoint {
    param($Body)

    trap {
        $TroubleshootingData.Error += $_
    }

    $TroubleshootingData = @{}
    $TroubleshootingData.Error = @()

    # Used to measure run times
    $StopWatch = [system.diagnostics.stopwatch]::StartNew()

    # Import Modules
    Import-Module CorkScrew
    Import-Module PowerAlto

    # $MyInvocation doesn't appear to exist for Endpoints, gotta set it manually
    $RootPath = $ArgumentList[0]

    $TsFile = Join-Path -Path $RootPath -ChildPath "ts.xml"
    $ConfigPath = Join-Path -Path $RootPath -ChildPath "config.json"

    # Setup Logging
    $Global:LogFile = Join-Path -Path $RootPath -ChildPath 'updaterule.log'
    $global:LogThreshold = 5

    log 1 "Starting updaterule" -LogHeader
    log 1 "ConfigPath: $ConfigPath"
    log 5 "Post Message: $Body"

    # Import Configuration
    log 5 "importing configuration"
    $Config = Get-CsConfiguration $ConfigPath

    # Update log threshold from config file
    $global:LogThreshold = $Config.LogThreshold

    # Setup LogDna
    if ($Config.SyslogApplication -and $Config.LogDnaApiKey -and $Config.LogDnaEnvironment) {
        $global:SyslogApplication = $Config.SyslogApplication
        $global:LogDnaEnvironment = $Config.LogDnaEnvironment

        # Create a credential to decode apikey
        log 5 "decrypting logdna apikey"
        $ApiKey = ConvertTo-SecureString $Config.LogDnaApiKey -Key $Config.AesKey
        $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'user', $ApiKey
        $global:LogDnaApiKey = $Credential.GetNetworkCredential().Password
    }

    # Create a credential to decode apikey
    log 5 "decrypting pa apikey"
    $ApiKey = ConvertTo-SecureString $Config.ApiKey -Key $Config.AesKey
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'user', $ApiKey
    $ApiKey = $Credential.GetNetworkCredential().Password

    try {
        log 5 "attempting to connect to palo alto firewall"
        $Connect = Get-PaDevice -DeviceAddress $Config.PaDevice -ApiKey $ApiKey
        log 5 "connection successful"
    } catch {
        log 1 "could not connect to pa, check ts.xml for details" -IsError
        $TroubleshootingData.Error += $_
    }

    # These tags are a minimum of what will be needed.
    $NeededTags = @()
    $NeededTags += 'vendor'
    $NeededTags += 'cpe'

    try {
        $GpEventRx = [regex] "GlobalProtect\ gateway\ client\ configuration\ (?<action>generated|released).\ User\ name:\ (?<user>.+?),"
        $GpMatch = $GpEventRx.Match($Body)
        if ($GpMatch.Success) {
            log 5 "post message matched successfully"
            # Extract what we need from the log message
            $Action = $GpMatch.Groups['action'].Value
            $User = $GpMatch.Groups['user'].Value

            # get just the user part of an email address to use as a tag for the vendor
            $NewTagRx = [regex] "(.+)(?=@)?"
            $UserTag = $NewTagRx.Match($User).Groups[0].Value

            # Get devices from api
            $Rest = @{}
            $Rest.Uri = "http://localhost:10005/api/getdevice/$UserTag"
            try {
                $Response = Invoke-RestMethod @Rest
            } catch {
                log 1 "could not connect to /getdevice api" -IsError
                break
            }
            $DeviceList = $Response

            # Get Address list from PA, may need to narrow this down later, but I didn't want to do multiple API calls.
            $CurrentAddresses = Get-PaAddress

            # Setup names for the new Group and Policy
            $GroupName = 'cpegrp_' + $UserTag
            $PolName = 'cpe_' + $UserTag

            switch ($Action) {
                'generated' {
                    log 2 "Creating rules for user $User"

                    ###################################
                    # Add Tags
                    $NeededTags += $UserTag
                    $CurrentTags = Get-PaTag
                    foreach ($tag in $NeededTags) {
                        $Lookup = $CurrentTags | Where-Object { $_.Name -eq $UserTag }
                        if (!($Lookup)) {
                            $CreateTag = New-PaTag -Name $tag
                            log 2 "Adding tag: $tag"
                        }
                    }
                    $TroubleshootingData.PaDevice = $global:padeviceobject

                    ###################################
                    # Add Address Objects
                    log 3 "Checking for $($DeviceList.Count) device(s)"
                    foreach ($d in $DeviceList) {
                        log 3 "$BaseMessage Looking up cpe: $d"
                        $Lookup = $CurrentAddresses | Where-Object { ($_.Value -eq $d) -or ($_.Value -eq "$d/32") }
                        if ($Lookup) {
                            log 4 "$d`: found"
                            if ($Lookup.Tags -notcontains $UserTag) {
                                log 4 "$d`: adding tag: $UserTag"
                                $Lookup | Set-PaAddress -Tag $UserTag
                                $TroubleshootingData.PaDevice = $global:padeviceobject
                            }
                        } else {
                            $Add = @{}
                            $Add.Name = 'cpe_' + $d + '-32'
                            $Add.Type = 'ip-netmask'
                            $Add.Value = "$d/32"
                            $Add.Tag = @('cpe', $UserTag)
                            log 4 "Creating address: $($Add.Name)"
                            $CreateAddress = Set-PaAddress @Add
                            $TroubleshootingData.PaDevice = $global:padeviceobject
                        }
                    }

                    ###################################
                    # Add Destination Address Group
                    $Filter = "'cpe' and '$UserTag'"
                    $Lookup = Get-PaAddressGroup -Name $GroupName
                    if ($Lookup) {
                        log 4 "Address Group exists"
                    } else {
                        $Add = @{}
                        $Add.Name = $GroupName
                        $Add.Filter = $Filter
                        log 4 "Creating Address Group: $($Add.Name)"
                        $AddGroup = Set-PaAddressGroup @Add
                    }

                    ###################################
                    # Add Create Security Policy

                    $Lookup = Get-PaSecurityPolicy -Name $PolName
                    if ($Lookup) {
                        log 3 "Security Policy exists"
                    } else {
                        $Add = @{}
                        $Add.Name = $PolName
                        $Add.SourceZone = $Config.SourceZone
                        $Add.DestinationZone = $Config.DestinationZone
                        $Add.SourceUser = $User
                        $Add.DestinationAddress = $GroupName
                        $Add.Action = 'allow'

                        log 4 "creating Security Policy $($Add.Name)"
                        $AddRule = Set-PaSecurityPolicy @Add

                        $Move = @{}
                        $Move.Name = $PolName
                        $Move.Top = $true

                        log 4 "Moving Security Policy $($Add.Name)"
                        $MoveRule = Move-PaSecurityPolicy @Move
                    }
                    break
                }
                'released' {
                    log 3 "removing config for user $User"
                    $RuleLookup = Get-PaSecurityPolicy -Name $PolName
                    $GroupLookup = Get-PaAddressGroup -Name $GroupName
                    $AddressLookup = $CurrentAddresses | Where-Object { $_.Tags -contains $UserTag }
                    $TagLookup = Get-PaTag -Name $UserTag

                    if ($RuleLookup) {
                        log 4 "removing rule: $($RuleLookup.Name)"
                        $RuleRemove = $RuleLookup | Remove-PaSecurityPolicy
                    }

                    if ($GroupLookup) {
                        log 4 "removing address group: $($GroupLookup.Name)"
                        $GroupRemove = $GroupLookup | Remove-PaAddressGroup
                    }

                    foreach ($address in $AddressLookup) {
                        log 4 "removing address: $($address.Name)"
                        $address | Remove-PaAddress
                    }

                    if ($TagLookup) {
                        log 4 "removing tag: $($TagLookup.Name)"
                        $TagRemove = $TagLookup | Remove-PaTag
                    }
                    break
                }
            }

            if ($Config.Commit) {
                log 1 "Commiting"
                $Commit = Invoke-PaCommit -Wait
            } else {
                log 1 "Commit set to false, skipping Commit..."
            }
        } else {
            log 1 "Invalid post message"
        }
        $TroubleshootingData.PaDevice = $global:padeviceobject
    } catch {
        $TroubleshootingData.PaDevice = $global:padeviceobject
        $TroubleshootingData.Error += $_
    }

    $StopWatch.Stop()
    $ScriptSeconds = $StopWatch.Elapsed.Seconds
    log 1 "Completed in $ScriptSeconds seconds"

    $TroubleshootingData | Export-Clixml -Path $TsFile -Force
}

Start-UDRestApi -Endpoint $Endpoint -Port 10004 -Name $ApiName