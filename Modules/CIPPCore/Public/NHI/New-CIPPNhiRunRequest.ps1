function New-CIPPNhiRunRequest {
    <#
    .SYNOPSIS
        Prepares a non-human identity (NHI) compromise investigation: the history row, the live-progress job and its orchestration.
    .DESCRIPTION
        Every way of starting a run goes through here so the run is visible the same way everywhere: a Waiting
        row in NhiReports (the history), an async-deployment job keyed on the case id (the live progress the
        page polls) and the input to hand to Start-CIPPOrchestrator: one Push-NHIRun job per phase of
        Get-CIPPNhiRunSteps, run in order on one worker (Sequential). Nothing is queued here; the caller
        starts one orchestration per investigation.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER ServicePrincipalId
        Object id of the service principal (enterprise app or managed identity) to investigate.
    .PARAMETER RequestedBy
        Who asked for the run.
    .PARAMETER RequestedFromIP
        The requesting technician's address (first x-forwarded-for hop): the run treats it as theirs, never the attacker's.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$ServicePrincipalId,
        [string]$RequestedBy = 'CIPP',
        [string]$RequestedFromIP
    )

    # Throws for a service principal that does not exist: there is nothing to investigate.
    $Sp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($ServicePrincipalId)?`$select=id,appId,displayName,servicePrincipalType" -tenantid $TenantFilter -AsApp $true
    $Name = if ([string]::IsNullOrWhiteSpace($Sp.displayName)) { $ServicePrincipalId } else { [string]$Sp.displayName }

    $CaseId = New-CIPPBecCaseId -Prefix 'NHI'
    $RunSteps = @(Get-CIPPNhiRunSteps)
    if ($PSCmdlet.ShouldProcess("$Name in $TenantFilter", "Prepare NHI investigation $CaseId")) {
        $Properties = @{
            ServicePrincipalId   = [string]$Sp.id
            AppId                = [string]$Sp.appId
            DisplayName          = $Name
            ServicePrincipalType = [string]$Sp.servicePrincipalType
            Status               = 'Waiting'
            RequestedBy          = $RequestedBy
            RequestedAt          = (Get-Date).ToUniversalTime().ToString('o')
        }
        if ($RequestedFromIP) { $Properties.RequestedFromIP = $RequestedFromIP }
        $null = Set-CIPPBecReport -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -Replace -Properties $Properties
        # keyed on the id: a display name can hold characters a table key cannot (/ \ # ?)
        $null = New-CIPPAsyncDeployment -JobId $CaseId -Names @([string]$Sp.id) -StepTitles @($RunSteps.Title) -Source 'NHI' -TenantFilter $TenantFilter
    }

    $Item = @{
        FunctionName       = 'NHIRun'
        ServicePrincipalId = [string]$Sp.id
        TenantFilter       = $TenantFilter
        SubjectName        = $Name
        CaseId             = $CaseId
    }
    if ($RequestedFromIP) { $Item.RequestedFromIP = $RequestedFromIP; $Item.RequestedBy = $RequestedBy }

    return [pscustomobject]@{
        CaseId      = $CaseId
        Name        = $Name
        Item        = $Item
        InputObject = [pscustomobject]@{
            OrchestratorName = "NHIRun_$CaseId"
            Batch            = @($RunSteps | ForEach-Object { $Item + @{ Step = $_.Key } })
            # each phase is its own job with its own timeout, run in order on one worker
            Sequential       = $true
            DurableMode      = 'Sequence'
            SkipLog          = $true
        }
    }
}
