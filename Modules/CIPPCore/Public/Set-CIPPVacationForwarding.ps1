function Set-CIPPVacationForwarding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TenantFilter,
        [Parameter(Mandatory)] [ValidateSet('Add', 'Remove')] [string]$Action,
        [object[]]$Users,
        [ValidateSet('internalAddress', 'ExternalAddress')] [string]$ForwardOption,
        [string]$ForwardInternal,
        [string]$ForwardExternal,
        [bool]$KeepCopy,
        [string]$APIName = 'Forwarding Vacation Mode',
        $Headers
    )

    $Results = [System.Collections.Generic.List[string]]::new()
    $Users = @($Users)

    foreach ($upn in $Users) {
        if ([string]::IsNullOrWhiteSpace($upn)) { continue }

        try {
            if ($Action -eq 'Remove') {
                $result = Set-CIPPForwarding -UserID $upn -Username $upn -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Disable $true
            } else {
                switch ($ForwardOption) {
                    'internalAddress' {
                        if ([string]::IsNullOrWhiteSpace($ForwardInternal)) {
                            throw 'ForwardInternal is required for internal forwarding.'
                        }

                        $result = Set-CIPPForwarding -UserID $upn -Username $upn -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName -Forward $ForwardInternal -KeepCopy $KeepCopy
                    }
                    'ExternalAddress' {
                        if ([string]::IsNullOrWhiteSpace($ForwardExternal)) {
                            throw 'ForwardExternal is required for external forwarding.'
                        }

                        $result = Set-CIPPForwarding -UserID $upn -Username $upn -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName -ForwardingSMTPAddress $ForwardExternal -KeepCopy $KeepCopy
                    }
                    default {
                        throw "Unsupported forward option: $ForwardOption"
                    }
                }
            }

            $Results.Add($result)
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Results.Add("Failed to set forwarding for ${upn}: $($ErrorMessage.NormalizedError)")
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to set forwarding for ${upn}: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        }
    }

    return $Results
}
