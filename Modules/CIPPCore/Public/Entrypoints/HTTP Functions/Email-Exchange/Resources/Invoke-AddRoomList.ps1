Function Invoke-AddRoomList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Room.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $Tenant = $Request.Body.tenantFilter ?? $Request.Body.tenantid

    $Results = [System.Collections.Generic.List[Object]]::new()
    $RoomListObject = $Request.Body

    # Construct email address from username and domain
    $EmailAddress = if ($RoomListObject.primDomain.value) {
        "$($RoomListObject.username)@$($RoomListObject.primDomain.value)"
    } else {
        "$($RoomListObject.username)@$($Tenant)"
    }

    # Parameters for New-DistributionGroup with RoomList
    $AddRoomListParams = @{
        Name               = $RoomListObject.username
        DisplayName        = $RoomListObject.displayName
        RoomList           = $true
        PrimarySMTPAddress = $EmailAddress
    }

    try {
        $AddRoomListRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'New-DistributionGroup' -cmdParams $AddRoomListParams
        $Results.Add("Successfully created room list: $($RoomListObject.displayName).")
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $Tenant -message "Created room list $($RoomListObject.displayName) with id $($AddRoomListRequest.identity)" -Sev 'Info'

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to create room list: $($RoomListObject.displayName). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Results.Add($Message)
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    $Body = [pscustomobject] @{ 'Results' = @($Results) }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
