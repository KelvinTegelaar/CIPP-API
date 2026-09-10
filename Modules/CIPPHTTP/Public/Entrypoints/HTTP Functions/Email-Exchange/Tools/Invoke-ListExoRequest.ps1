function Invoke-ListExoRequest {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Executes an arbitrary read-only Exchange Online cmdlet (Get-* or Search-*) for a tenant. Accepts cmdlet name and parameters in the request body.
    #>
    param($Request, $TriggerMetadata)
    try {
        $AllowedVerbs = @(
            'Get'
            'Search'
        )

        $Cmdlet = $Request.Body.Cmdlet
        # Parameters to splat onto the Exchange cmdlet, as an object of name/value pairs
        # (e.g. { "Identity": "user@contoso.com" }). Cast to an object so the generated schema
        # types cmdParams as an object rather than a string - a string-typed schema made the
        # client reject an object body, leaving no way to pass parameters.
        $cmdParams = if ($Request.Body.cmdParams) { [pscustomobject]$Request.Body.cmdParams } else { [PSCustomObject]@{} }
        $Verb = ($Cmdlet -split '-')[0]

        $TenantFilter = $Request.Body.TenantFilter
        if ($Request.Body.AvailableCmdlets) {
            $ExoRequest = @{
                TenantID         = $TenantFilter
                AvailableCmdlets = $true
            }
            if ($Request.Body.AsApp -eq $true) {
                $ExoRequest.AsApp = $true
            }
            if ($Request.Body.Compliance -eq $true) {
                $ExoRequest.Compliance = $true
            }
            $Results = New-ExoRequest @ExoRequest
            $Body = [PSCustomObject]@{
                Results  = $Results | Select-Object @{ Name = 'Cmdlet'; Expression = { $_ } }
                Metadata = @{
                    Count = ($Results | Measure-Object).Count
                }
            }
        } else {
            if ($AllowedVerbs -notcontains $Verb) {
                $Body = [PSCustomObject]@{
                    Results = "Invalid cmdlet: $Cmdlet"
                }
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = $Body
                    })
                return
            }

            $ExoParams = @{
                Cmdlet    = $Cmdlet
                cmdParams = $cmdParams
                tenantid  = $TenantFilter
            }

            if ($Request.Body.Select) {
                $ExoParams.Select = $Request.Body.Select
            }

            if ($Request.Body.UseSystemMailbox -eq $true) {
                $ExoParams.useSystemMailbox = $true
            }

            if ($Request.Body.Anchor) {
                $ExoParams.Anchor = $Request.Body.Anchor
            }

            if ($Request.Body.Compliance -eq $true) {
                $ExoParams.Compliance = $true
            }

            if ($Request.Body.AsApp -eq $true) {
                $ExoParams.AsApp = $true
            }

            try {
                $Results = New-ExoRequest @ExoParams
                $Body = [pscustomobject]@{
                    Results = $Results
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $Body = [pscustomobject]@{
                    Results = @(@{ Error = $ErrorMessage })
                }
            }
        }
    } catch {
        Write-Information "ExoRequest Error: $($_.Exception.Message)"
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -InputObject $Body -Compress
        })
}
