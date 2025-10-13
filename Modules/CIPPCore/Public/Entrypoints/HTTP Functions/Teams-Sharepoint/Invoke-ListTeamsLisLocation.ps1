Function Invoke-ListTeamsLisLocation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.TenantFilter
    try {
        $EmergencyLocations = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Get-CsOnlineLisLocation'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $EmergencyLocations = $ErrorMessage
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($EmergencyLocations)
        })

}
