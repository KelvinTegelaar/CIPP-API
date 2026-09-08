Function Invoke-ExecOneDriveShortCut {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    # Interact with the body of the request
    $TenantFilter = $Request.Body.tenantFilter
    $Username = $Request.Body.username
    $UserId = $Request.Body.userid
    $URL = $Request.Body.siteUrl.value
    $Destination = $Request.Body.destination
    if ($Destination -is [psobject] -and $Destination.value) {
        $Destination = $Destination.value
    }
    if ([string]::IsNullOrWhiteSpace([string]$Destination)) {
        $Destination = 'root'
    }

    Try {
        $Result = New-CIPPOneDriveShortCut -Username $Username -UserId $UserId -TenantFilter $TenantFilter -URL $URL -Destination $Destination -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
