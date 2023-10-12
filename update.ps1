#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Update
#
# Version: 1.0.0.0
#####################################################

#region Config
$Config = $Configuration | ConvertFrom-Json
#endregion Config

#region default properties
$p = $person | ConvertFrom-Json
$m = $manager | ConvertFrom-Json
$pp = $previousPerson | ConvertFrom-Json
$pd = $personDifferences | ConvertFrom-Json

$aRef = $accountReference | ConvertFrom-Json
$mRef = $managerAccountReference | ConvertFrom-Json

$auditLogs = [Collections.Generic.List[PSCustomObject]]::new()
#endregion default properties

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = @(
    [Net.SecurityProtocolType]::Tls
    [Net.SecurityProtocolType]::Tls11
    [Net.SecurityProtocolType]::Tls12
)

#region functions
function Get-SurName {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $person
    )

    process {
        $FamilyName = "$($person.name.FamilyNamePrefix) $($person.name.FamilyName)".Trim()
        $PartnerName = "$($person.name.FamilyNamePartnerPrefix) $($person.name.FamilyNamePartner)".Trim()

        switch ($person.name.convention) {
            'B' {
                return $FamilyName
            }
            'P' {
                return $PartnerName
            }
            'BP' {
                return "$($FamilyName) - $($PartnerName)"
            }
            'PB' {
                return "$($PartnerName) - $($FamilyName)"
            }
        }
    }
}


function Get-DisplayName {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $person
    )

    process {
        if ([string]::IsNullOrEmpty($person.Name.Nickname)) {
            $FirstName = $person.Name.GivenName
        }
        else {
            $FirstName = $person.Name.Nickname
        }

        $SurName = Get-SurName -person $person

        Write-Output "$($FirstName) $($SurName)"
    }
}


function Get-LisaAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]
        $TenantId,

        [Parameter(Mandatory)]
        [string]
        $ClientId,

        [Parameter(Mandatory)]
        [string]
        $ClientSecret,

        [Parameter(Mandatory)]
        [string]
        $Scope
    )

    try {
        $RestMethod = @{
            Uri         = "https://login.microsoftonline.com/$($TenantId)/oauth2/v2.0/token/"
            ContentType = "application/x-www-form-urlencoded"
            Method      = "Post"
            Body        = @{
                grant_type    = "client_credentials"
                client_id     = $ClientId
                client_secret = $ClientSecret
                scope         = $Scope
            }
        }
        Invoke-RestMethod @RestMethod
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Resolve-HTTPError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $httpError = [PSCustomObject]@{
            FullyQualifiedErrorId = $ErrorObject.FullyQualifiedErrorId
            MyCommand             = $ErrorObject.InvocationInfo.MyCommand
            RequestUri            = $ErrorObject.TargetObject.RequestUri
            ScriptStackTrace      = $ErrorObject.ScriptStackTrace
            ErrorMessage          = ''
        }

        if ($ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') {
            $httpError.ErrorMessage = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            $httpError.ErrorMessage = [System.IO.StreamReader]::new(
                $ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
        }

        Write-Output $httpError
    }
}


function Get-ErrorMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]
        $ErrorObject
    )

    process {
        $errorMessage = [PSCustomObject]@{
            VerboseErrorMessage = $null
            AuditErrorMessage   = $null
        }

        if (
            $ErrorObject.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException' -or
            $ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException'
        ) {
            $httpErrorObject = Resolve-HTTPError -Error $ErrorObject

            $errorMessage.VerboseErrorMessage = $httpErrorObject.ErrorMessage
            $errorMessage.AuditErrorMessage = $httpErrorObject.ErrorMessage
        }

        # If error message empty, fall back on $ex.Exception.Message
        if ([String]::IsNullOrEmpty($errorMessage.VerboseErrorMessage)) {
            $errorMessage.VerboseErrorMessage = $ErrorObject.Exception.Message
        }
        if ([String]::IsNullOrEmpty($errorMessage.AuditErrorMessage)) {
            $errorMessage.AuditErrorMessage = $ErrorObject.Exception.Message
        }

        Write-Output $errorMessage
    }
}
#endregion functions

# Build the Final Account object
$Account = @{
    givenName      = $p.Name.NickName
    surName        = Get-SurName $p
    displayName    = Get-DisplayName $p

    employeeId     = $p.ExternalId
    officeLocation = $p.PrimaryContract.Department.DisplayName
    department     = $p.PrimaryContract.Department.DisplayName
    jobTitle       = $p.PrimaryContract.Title.Name
    companyName    = $p.PrimaryContract.Organization.Name
    # businessPhones = @("$($p.Contact.Business.Phone.Mobile)")
}

$Success = $False

# Start Script
try {
    Write-Verbose 'Getting accessToken'

    $splatGetTokenParams = @{
        TenantId     = $Config.TenantId
        ClientId     = $Config.ClientId
        ClientSecret = $Config.ClientSecret
        Scope        = $Config.Scope
    }

    $accessToken = (Get-LisaAccessToken @splatGetTokenParams).access_token

    $authorizationHeaders = [System.Collections.Generic.Dictionary[[String],[String]]]::new()
    $authorizationHeaders.Add("Authorization", "Bearer $accessToken")
    $authorizationHeaders.Add("Content-Type", "application/json")
    $authorizationHeaders.Add("Mwp-Api-Version", "1.0")

    #Get previous account, select only $Account.Keys
    $splatParams = @{
        Uri     = "$($Config.BaseUrl)/Users/$($aRef)"
        Method  = 'Get'
        Headers = $authorizationHeaders
    }
    $PreviousAccount = Invoke-RestMethod @splatParams | Select-Object $Account.Keys

    Write-Verbose "Updating KPN Lisa account for '$($p.DisplayName)'"

    $splatParams = @{
        Uri     = "$($Config.BaseUrl)/Users/$($aRef)/bulk"
        Method  = 'Patch'
        Headers = $authorizationHeaders
        Body    = ($Account | convertto-json)
    }

    if (-not($dryRun -eq $true)) {
        [void] (Invoke-RestMethod @splatParams)
    }

    $AuditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount" # Optionally specify a different action for this audit log
            Message = "Account for '$($p.DisplayName)' Updated. ObjectId: '$($aRef)'"
            IsError = $false
        })

    # Updating manager
    if ($null -eq $mRef) {
        $splatDeleteManagerParams = @{
            Uri     = "$($Config.BaseUrl)/Users/$($aRef)/manager"
            Method  = 'Delete'
            Headers = $authorizationHeaders
        }

        # TODO:: validate return value on update and delete for manager
        if (-not($dryRun -eq $true)) {
            [void] (Invoke-RestMethod @splatDeleteManagerParams)
        }

        $success = $true

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                Message = "Manager for '$($p.DisplayName)' deleted. ObjectId: '$($userResponse.objectId)'"
                IsError = $false
            })
    }
    else {
        $splatUpdateManagerParams = @{
            Uri     = "$($Config.BaseUrl)/Users/$($aRef)/Manager"
            Method  = 'Put'
            Headers = $authorizationHeaders
            Body    = ($mRef | ConvertTo-Json)
        }

        # TODO:: validate return value on update and delete for manager
        if (-not($dryRun -eq $true)) {
            [void] (Invoke-RestMethod @splatUpdateManagerParams)
        }

        $success = $true

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                Message = "Manager for '$($p.DisplayName)' Updated. ObjectId: '$($userResponse.objectId)'"
                IsError = $false
            })
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage) [$($ex.ErrorDetails.Message)]"

    $auditLogs.Add([PSCustomObject]@{
            Action  = "UpdateAccount" # Optionally specify a different action for this audit log
            Message = "Error updating account [$($account.DisplayName) ($($aRef))]. Error Message: $($errorMessage.AuditErrorMessage)."
            IsError = $True
        })
}

# Send results
$Result = [PSCustomObject]@{
    Success          = $Success
    AuditLogs        = $AuditLogs
    Account          = $Account
    PreviousAccount  = $PreviousAccount

    # Optionally return data for use in other systems
    ExportData      = [PSCustomObject]@{
        AccountReference  = $aRef
        userPrincipalName = $PreviousAccount.userPrincipalName
        employeeId        = $Account.employeeId
        displayName       = $Account.displayName
        mail              = $PreviousAccount.mail
    }
}

Write-Output $Result | ConvertTo-Json -Depth 10
