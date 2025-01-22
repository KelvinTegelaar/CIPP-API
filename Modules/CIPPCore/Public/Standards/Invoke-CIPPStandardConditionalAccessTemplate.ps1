function Invoke-CIPPStandardConditionalAccessTemplate {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'ConditionalAccess'

    If ($Settings.remediate -eq $true) {

        $APINAME = 'Standards'

        foreach ($Setting in $Settings) {
            try {

                $Table = Get-CippTable -tablename 'templates'
                $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$($Setting.TemplateList.value)'"
                $JSONObj = (Get-CippAzDataTableEntity @Table -Filter $Filter).JSON
                $null = New-CIPPCAPolicy -TenantFilter $tenant -state $Setting.state -RawJSON $JSONObj -Overwrite $true -APIName $APIName -ExecutingUser $request.headers.'x-ms-client-principal' -ReplacePattern 'displayName'
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update conditional access rule $($JSONObj.displayName). Error: $ErrorMessage" -sev 'Error'
            }
        }


    }
}
