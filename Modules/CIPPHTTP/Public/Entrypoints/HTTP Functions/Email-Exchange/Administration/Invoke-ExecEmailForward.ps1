Function Invoke-ExecEmailForward {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APINAME-message 'Accessed this API' -Sev 'Debug'


    $TenantFilter = $Request.Body.tenantFilter
    $Username = $Request.Body.userID
    if ($Request.Body.ForwardInternal -is [string]) {
        $ForwardingAddress = $Request.Body.ForwardInternal
    } else {
        $ForwardingAddress = $Request.Body.ForwardInternal.value
    }
    $ForwardingSMTPAddress = $Request.Body.ForwardExternal
    $ForwardOption = $Request.Body.forwardOption
    [bool]$KeepCopy = if ($Request.Body.KeepCopy -eq 'true') { $true } else { $false }

    # Process the forwarding option based on the type selected
    switch ($ForwardOption) {
        'internalAddress' {
            # Set up internal forwarding to another mailbox within the organization
            try {
                $Results = Set-CIPPForwarding -UserID $Username -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -Forward $ForwardingAddress -KeepCopy $KeepCopy
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $Results = $_.Exception.Message
                $StatusCode = [HttpStatusCode]::InternalServerError
            }
        }
        'ExternalAddress' {
            # Set up external forwarding to an SMTP address outside the organization
            try {
                $Results = Set-CIPPForwarding -UserID $Username -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -ForwardingSMTPAddress $ForwardingSMTPAddress -KeepCopy $KeepCopy
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $Results = $_.Exception.Message
                $StatusCode = [HttpStatusCode]::InternalServerError
            }
        }
        'disabled' {
            # Disable email forwarding for the specified user
            try {
                $Results = Set-CIPPForwarding -UserID $Username -Username $Username -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Disable $true
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $Results = $_.Exception.Message
                $StatusCode = [HttpStatusCode]::InternalServerError
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = @($Results) }
        })

}
