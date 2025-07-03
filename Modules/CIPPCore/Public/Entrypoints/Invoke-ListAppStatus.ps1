using namespace System.Net

function Invoke-ListAppStatus {
    <#
    .SYNOPSIS
    List application installation status for devices
    
    .DESCRIPTION
    Retrieves application installation status and details for devices in a tenant using Microsoft Graph API
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Device.Read
        
    .NOTES
    Group: Device Management
    Summary: List App Status
    Description: Retrieves application installation status and details for devices in a tenant using Microsoft Graph API, including installation state, error codes, and device information
    Tags: Device Management,Applications,Installation Status,Graph API
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Parameter: AppFilter (string) [query] - Application ID to filter results by
    Response: Returns an array of device application status objects with the following properties:
    Response: - DeviceName (string): Name of the device
    Response: - UserPrincipalName (string): User principal name
    Response: - Platform (string): Device platform (Windows, iOS, Android, etc.)
    Response: - AppVersion (string): Application version
    Response: - InstallState (string): Installation state (installed, failed, notInstalled, etc.)
    Response: - InstallStateDetail (string): Detailed installation state information
    Response: - LastModifiedDateTime (string): Last modification date and time
    Response: - DeviceId (string): Device unique identifier
    Response: - ErrorCode (string): Error code if installation failed
    Response: - UserName (string): User display name
    Response: - UserId (string): User unique identifier
    Response: - ApplicationId (string): Application unique identifier
    Response: - AssignmentFilterIdsList (string): Assignment filter IDs
    Response: - AppInstallState (string): Application installation state
    Response: - AppInstallStateDetails (string): Detailed application installation state
    Response: - HexErrorCode (string): Hexadecimal error code
    Response: On error: Error message with HTTP 403 status
    Example: [
      {
        "DeviceName": "DESKTOP-ABC123",
        "UserPrincipalName": "john.doe@contoso.com",
        "Platform": "Windows",
        "AppVersion": "1.0.0.0",
        "InstallState": "installed",
        "InstallStateDetail": "Successfully installed",
        "LastModifiedDateTime": "2024-01-15T10:30:00Z",
        "DeviceId": "12345678-1234-1234-1234-123456789012",
        "ErrorCode": "",
        "UserName": "John Doe",
        "UserId": "87654321-4321-4321-4321-210987654321",
        "ApplicationId": "app-123",
        "AssignmentFilterIdsList": "",
        "AppInstallState": "installed",
        "AppInstallStateDetails": "Successfully installed",
        "HexErrorCode": ""
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $appFilter = $Request.Query.AppFilter
    Write-Host "Using $appFilter"
    $body = @"
{"select":["DeviceName","UserPrincipalName","Platform","AppVersion","InstallState","InstallStateDetail","LastModifiedDateTime","DeviceId","ErrorCode","UserName","UserId","ApplicationId","AssignmentFilterIdsList","AppInstallState","AppInstallStateDetails","HexErrorCode"],"skip":0,"top":999,"filter":"(ApplicationId eq '$Appfilter')","orderBy":[]}
"@
    try {
        $GraphRequest = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/reports/getDeviceInstallStatusReport' -tenantid $TenantFilter -body $body
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
