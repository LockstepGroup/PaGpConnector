#Requires -Modules UniversalDashboard

$RootDirectory = Split-Path -Path $MyInvocation.MyCommand.Path

$ApiName = "getdevice"
$Endpoint = New-UDEndpoint -Url "/getdevice/:user" -Method "GET" -ArgumentList $RootDirectory -Endpoint {
    $DeviceMappingCsv = Join-Path -Path $ArgumentList[0] -ChildPath 'DummyData.csv'
    $DeviceMapping = Import-Csv -Path $DeviceMappingCsv
    $Devices = $DeviceMapping | Where-Object { $_.Username -eq $user }

    if ($Devices) {
        $Devices.IpAddress | ConvertTo-Json
    } else {
        @{
            status  = "error"
            message = "user not found"
        } | ConvertTo-Json
    }
}

Start-UDRestApi -Endpoint $Endpoint -Port 10005 -Name $ApiName