function Invoke-CippTestSecuritySimulation_PasswordSprayNoMfa {
    <#
    .SYNOPSIS
    Security Simulation - Password spray on an account without MFA

    .DESCRIPTION
    An attacker guesses a common password for an account that has no MFA registered and signs in unchallenged.
    #>
    param($Tenant)

    Invoke-CippSecuritySimulationTest -Tenant $Tenant -ScenarioId 'PasswordSprayNoMfa'
}