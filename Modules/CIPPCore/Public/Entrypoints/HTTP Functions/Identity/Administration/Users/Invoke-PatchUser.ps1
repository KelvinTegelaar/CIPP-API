function Invoke-PatchUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $tenantFilter = $Request.Body.tenantFilter
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $HttpResponse = [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{'Results' = @("Default response, you should never see this.") }
    }

    try {
        $UserObj = $Request.Body | Select-Object -Property * -ExcludeProperty tenantFilter
        if ([string]::IsNullOrWhiteSpace($UserObj.id)) {
            $HttpResponse.StatusCode = [HttpStatusCode]::BadRequest
            $HttpResponse.Body = @{'Results' = @('Failed to patch user. No user ID provided') }
        } else {
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($UserObj.id)" -tenantid $tenantFilter -type PATCH -body $($UserObj | ConvertTo-Json)
            $HttpResponse.Body = @{'Results' = @("Properties on user $($UserObj.id) patched successfully") }
        }

    } catch {
        $HttpResponse.StatusCode = [HttpStatusCode]::InternalServerError
        $HttpResponse.Body = @{'Results' = @("Failed to patch user. Error: $($_.Exception.Message)") }
    }

    Push-OutputBinding -Name Response -Value $HttpResponse
}