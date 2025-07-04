using namespace System.Net

function Invoke-ExecEmailForward {
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
    $KeepCopy = if ($Request.Body.KeepCopy -eq 'true') { $true } else { $false }

    # Process the forwarding option based on the type selected
    try {
        switch ($ForwardOption) {
            'internalAddress' {
                # Set up internal forwarding to another mailbox within the organization
                $Results = Set-CIPPForwarding -UserID $Username -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -Forward $ForwardingAddress -KeepCopy $KeepCopy
            }
            'ExternalAddress' {
                # Set up external forwarding to an SMTP address outside the organization
                $Results = Set-CIPPForwarding -UserID $Username -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -ForwardingSMTPAddress $ForwardingSMTPAddress -KeepCopy $KeepCopy
            }
            'disabled' {
                # Disable email forwarding for the specified user
                $Results = Set-CIPPForwarding -UserID $Username -Username $Username -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Disable $true
            }
            default {
                throw "Invalid forwarding option: $ForwardOption"
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    }

}
