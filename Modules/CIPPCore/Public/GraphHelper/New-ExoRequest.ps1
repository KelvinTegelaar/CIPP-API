function New-ExoRequest {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(DefaultParameterSetName = 'ExoRequest')]
    Param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ExoRequest')]
        [string]$cmdlet,

        [Parameter(Mandatory = $false, ParameterSetName = 'ExoRequest')]
        $cmdParams,

        [Parameter(Mandatory = $false, ParameterSetName = 'ExoRequest')]
        [string]$Select,

        [Parameter(Mandatory = $false, ParameterSetName = 'ExoRequest')]
        [string]$Anchor,

        [Parameter(Mandatory = $false, ParameterSetName = 'ExoRequest')]
        [bool]$useSystemMailbox,

        [string]$tenantid,

        [bool]$NoAuthCheck,

        [switch]$Compliance,
        [ValidateSet('v1.0', 'beta')]
        [string]$ApiVersion = 'beta',

        [Parameter(ParameterSetName = 'AvailableCmdlets')]
        [switch]$AvailableCmdlets,

        $ModuleVersion = '3.7.1',
        [switch]$AsApp
    )
    if ((Get-AuthorisedRequest -TenantID $tenantid) -or $NoAuthCheck -eq $True) {
        if ($Compliance.IsPresent) {
            $Resource = 'https://ps.compliance.protection.outlook.com'
        } else {
            $Resource = 'https://outlook.office365.com'
        }
        $token = Get-GraphToken -Tenantid $tenantid -scope "$Resource/.default" -AsApp:$AsApp.IsPresent

        if ($cmdParams) {
            #if cmdparams is a pscustomobject, convert to hashtable, otherwise leave as is
            $Params = $cmdParams
        } else {
            $Params = @{}
        }
        $ExoBody = ConvertTo-Json -Depth 5 -Compress -InputObject @{
            CmdletInput = @{
                CmdletName = $cmdlet
                Parameters = $Params
            }
        }
        $ExoBody = Get-CIPPTextReplacement -TenantFilter $tenantid -Text $ExoBody

        $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $tenantid -or $_.customerId -eq $tenantid }
        if (-not $Tenant -and $NoAuthCheck -eq $true) {
            $Tenant = [PSCustomObject]@{
                customerId = $tenantid
            }
        }
        if (!$Anchor) {
            $MailboxGuid = 'bb558c35-97f1-4cb9-8ff7-d53741dc928c'
            if ($cmdlet -in 'Set-AdminAuditLogConfig') {
                $MailboxGuid = '8cc370d3-822a-4ab8-a926-bb94bd0641a9'
            }
            if ($Compliance.IsPresent) {
                $Anchor = "UPN:SystemMailbox{$MailboxGuid}@$($tenant.initialDomainName)"
            } else {
                $anchor = "APP:SystemMailbox{$MailboxGuid}@$($tenant.customerId)"
            }
        }
        #if the anchor is a GUID, try looking up the user.
        if ($Anchor -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            Write-Verbose "Anchor is a GUID, looking up user. GUID is $Anchor"
            $NewAnchor = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$Anchor/?`$select=UserPrincipalName,id" -tenantid $tenantid -NoAuthCheck $NoAuthCheck
            if ($NewAnchor) {
                $Anchor = $NewAnchor.UserPrincipalName
                Write-Verbose "Found GUID, using $Anchor"
            } else {
                Write-Error "Failed to find user with GUID $Anchor"
            }
        }

        Write-Verbose "Using $Anchor"

        $Headers = @{
            Authorization     = $Token.Authorization
            Prefer            = 'odata.maxpagesize=1000'
            'X-AnchorMailbox' = $anchor
        }

        # Compliance API trickery. Capture Location headers on redirect, extract subdomain and prepend to compliance URL
        if ($Compliance.IsPresent) {
            if (!$Tenant.ComplianceUrl) {
                Write-Verbose "Getting Compliance URL for $($tenant.defaultDomainName)"
                $URL = "$Resource/adminapi/$ApiVersion/$($tenant.customerId)/EXOBanner('AutogenSession')?Version=$ModuleVersion"
                Invoke-RestMethod -ResponseHeadersVariable ComplianceHeaders -MaximumRedirection 0 -ErrorAction SilentlyContinue -Uri $URL -Headers $Headers -SkipHttpErrorCheck | Out-Null
                $RedirectedHost = ([System.Uri]($ComplianceHeaders.Location | Select-Object -First 1)).Host
                $RedirectedHostname = '{0}.ps.compliance.protection.outlook.com' -f ($RedirectedHost -split '\.' | Select-Object -First 1)
                $Resource = "https://$($RedirectedHostname)"
                try {
                    $null = [System.Uri]$Resource
                    $Tenant | Add-Member -MemberType NoteProperty -Name ComplianceUrl -Value $Resource
                    $TenantTable = Get-CIPPTable -tablename 'Tenants'
                    Add-CIPPAzDataTableEntity @TenantTable -Entity $Tenant -Force
                } catch {
                    Write-Error "Failed to get the Compliance URL for $($tenant.defaultDomainName), invalid URL - check the Anchor and try again."
                    return
                }
            } else {
                $Resource = $Tenant.ComplianceUrl
            }
            Write-Verbose "Redirecting to $Resource"
        }

        if ($PSCmdlet.ParameterSetName -eq 'AvailableCmdlets') {
            $Headers.CommandName = '*'
            $URL = "$Resource/adminapi/v1.0/$($tenant.customerId)/EXOModuleFile?Version=$ModuleVersion"
            Write-Verbose "GET [ $URL ]"
            return (Invoke-RestMethod -Uri $URL -Headers $Headers).value.exportedCmdlets -split ',' | Where-Object { $_ } | Sort-Object
        }

        if ($PSCmdlet.ParameterSetName -eq 'ExoRequest') {
            try {
                if ($Select) { $Select = "?`$select=$Select" }
                $URL = "$Resource/adminapi/$ApiVersion/$($tenant.customerId)/InvokeCommand$Select"

                Write-Verbose "POST [ $URL ]"
                $ReturnedData = do {
                    $ExoRequestParams = @{
                        Uri         = $URL
                        Method      = 'POST'
                        Body        = $ExoBody
                        Headers     = $Headers
                        ContentType = 'application/json; charset=utf-8'
                    }

                    $Return = Invoke-RestMethod @ExoRequestParams -ResponseHeadersVariable ResponseHeaders
                    $URL = $Return.'@odata.nextLink'
                    $Return
                } until ($null -eq $URL)

                Write-Verbose ($ResponseHeaders | ConvertTo-Json)
                if ($ReturnedData.'@adminapi.warnings' -and $ReturnedData.value -eq $null) {
                    $ReturnedData.value = $ReturnedData.'@adminapi.warnings'
                }
            } catch {
                $ErrorMess = $($_.Exception.Message)
                try {
                    $ReportedError = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue)
                    $Message = if ($ReportedError.error.details.message) {
                        $ReportedError.error.details.message
                    } elseif ($ReportedError.error.innererror) {
                        $ReportedError.error.innererror.internalException.message
                    } elseif ($ReportedError.error.message) { $ReportedError.error.message }
                } catch { $Message = $_.ErrorDetails }
                if ($null -eq $Message) { $Message = $ErrorMess }
                throw $Message
            }
            return $ReturnedData.value
        }
    } else {
        Write-Error 'Not allowed. You cannot manage your own tenant or tenants not under your scope'
    }
}
