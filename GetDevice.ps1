#Requires -Modules UniversalDashboard

$ApiName = "getdevice"
$Endpoint = New-UDEndpoint -Url "/getdevice/:user" -Method "GET" -Endpoint {
    $DeviceMapping = @{
        "VendorA" = @(
            '10.89.89.2'
            '10.89.89.3'
            '10.89.89.4'
        )
        "VendorB" = @(
            '10.89.90.2'
            '10.89.90.3'
            '10.89.90.4'
        )
        "VendorC" = @(
            '10.89.91.2'
            '10.89.91.3'
            '10.89.91.4'
        )
    }
    $Devices = $DeviceMapping.$user
    if ($Devices) {
        $Devices | ConvertTo-Json
    } else {
        @{
            status  = "error"
            message = "user not found"
        } | ConvertTo-Json
    }
}

Start-UDRestApi -Endpoint $Endpoint -Port 10005 -Name $ApiName