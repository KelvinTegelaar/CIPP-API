function Push-ExecAddDefenderIndicator {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $APIName = 'AddDefenderIndicator'
    $Headers = $Item.AuditHeaders
    $QueueId = [string]$Item.QueueId
    $Values = [string[]]@($Item.Values)
    $Template = @{}
    $Document = [System.Text.Json.JsonDocument]::Parse([string]$Item.TemplateJson)
    try {
        foreach ($Field in $Document.RootElement.EnumerateObject()) {
            $Template[$Field.Name] = if ($Field.Name -eq 'generateAlert') { $Field.Value.GetBoolean() } else { $Field.Value.GetString() }
        }
    } finally {
        $Document.Dispose()
    }
    $Expiry = if ($Template.expirationTime) {
        [datetimeoffset]::ParseExact($Template.expirationTime, "yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
    }
    $Label = "$($Template.action) $($Template.indicatorType)"

    try {
        $Tenant = foreach ($Candidate in @(Get-Tenants -TenantFilter $Item.TenantId -ErrorAction Stop)) {
            if ($Candidate.customerId -eq $Item.TenantId) { $Candidate; break }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Did not add $($Values.Count) $Label indicators: CIPP could not look up tenant $($Item.Tenant). $($ErrorMessage.NormalizedError) (queue $QueueId)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $Item.Tenant -tenantId $Item.TenantId -message $Message -sev Error -LogData @{ QueueId = $QueueId; Results = @() }
        throw $Message
    }
    if (-not $Tenant) {
        $Message = "Did not add $($Values.Count) $Label indicators to tenant $($Item.Tenant): CIPP no longer manages it, or it is excluded (queue $QueueId)"
        Write-LogMessage -headers $Headers -API $APIName -tenantId $Item.TenantId -message $Message -sev Error -LogData @{ QueueId = $QueueId; Results = @() }
        throw $Message
    }
    $Domain = $Tenant.defaultDomainName
    if ($Expiry -and $Expiry -le [datetimeoffset]::UtcNow) {
        $Message = "Did not add $($Values.Count) $Label indicators in $($Domain): their expiry, $($Template.expirationTime), passed before the task ran (queue $QueueId)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $Domain -tenantId $Tenant.customerId -message $Message -sev Error -LogData @{ QueueId = $QueueId; Results = @() }
        throw $Message
    }

    $Outcome = Add-CIPPDefenderIndicator -TenantFilter $Domain -TenantId $Tenant.customerId -Values $Values -Template $Template -Headers $Headers -APIName $APIName -QueueId $QueueId
    if ($Outcome.Failed -gt 0) {
        throw "$($Outcome.Failed) of $($Values.Count) $Label indicators in $Domain were skipped, refused or not confirmed by Defender. Check the logbook entry for queue $QueueId and the Indicators page before adding them again."
    }
}
