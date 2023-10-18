function Set-CIPPGDAPAutoExtend {
    [CmdletBinding()]
    param (
        $RelationShipid,
        [switch]$All,
        $APIName = "Set GDAP Auto Exension",
        $ExecutingUser
    )

    $ReturnedData = if ($All -eq $true) {
        $Relationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships" -tenantid $env:tenantid -NoAuthCheck $true
        foreach ($Relation in $Relationships) {
            try {
                $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($Relation.id)" -tenantid $env:tenantid -type PATCH -body '{"autoExtendDuration":"P180D"}' -Verbose -NoAuthCheck $true
                write-LogMessage -user $ExecutingUser -API $APIName -message "Successfully set auto renew for $($Relation.id)" -Sev "Info"
                "Successfully set auto renew for $($Relation.id)" 
    
            }
            catch {
                $ErrorMessage = $_.Exception.Message
                $CleanError = Get-NormalizedError -message $ErrorMessage
                "Could not set auto renewal for $($Relation.id): $CleanError"
            }

        }
    }
    else {
        try {
            $GraphRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($RelationShipid)" -tenantid $env:tenantid -type PATCH -body '{"autoExtendDuration":"P180D"}' -Verbose -NoAuthCheck $true
            write-LogMessage -user $ExecutingUser -API $APIName -message "Successfully set auto renew for $($RelationShipid)" -Sev "Info"
            @("Successfully set auto renew for $($RelationShipid)" )
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            $CleanError = Get-NormalizedError -message $ErrorMessage
            "Could not set auto renewal for $($RelationShipid): $CleanError"
        }
    }

    return $ReturnedData

}