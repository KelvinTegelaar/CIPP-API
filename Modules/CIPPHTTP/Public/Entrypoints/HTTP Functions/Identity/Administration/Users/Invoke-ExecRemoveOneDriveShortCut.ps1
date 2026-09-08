Function Invoke-ExecRemoveOneDriveShortCut {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter
    $Username = $Request.Body.username
    if ($Username -is [psobject] -and $Username.value) { $Username = $Username.value }
    $ItemId = $Request.Body.id
    if ($ItemId -is [psobject] -and $ItemId.value) { $ItemId = $ItemId.value }
    $Name = $Request.Body.name
    if ($Name -is [psobject] -and $Name.value) { $Name = $Name.value }

    try {
        if ([string]::IsNullOrWhiteSpace($Username) -or [string]::IsNullOrWhiteSpace($ItemId)) {
            throw 'username and id are required to remove an OneDrive shortcut'
        }
        $EscapedUser = [System.Uri]::EscapeDataString($Username)
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/users/$EscapedUser/drive/items/$ItemId" -tenantid $TenantFilter -type 'DELETE' -asapp $true
        $Label = if ($Name) { "'$Name'" } else { $ItemId }
        $Result = "Removed OneDrive shortcut $Label for $Username"
        Write-LogMessage -API 'Remove OneDrive shortcut' -headers $Headers -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not remove OneDrive shortcut for $Username : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API 'Remove OneDrive shortcut' -headers $Headers -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
