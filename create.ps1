#####################################################
# HelloID-Conn-Prov-Target-KPN-Lisa-Create
#
# Version: 1.0.0.0
#####################################################

#region Config
$Config = $Configuration | ConvertFrom-Json
#endregion Config

#region default properties
$p = $Person | ConvertFrom-Json
$m = $Manager | ConvertFrom-Json

$aRef = $null # New-Guid
$mRef = $managerAccountReference | ConvertFrom-Json

$AuditLogs = [Collections.Generic.List[PSCustomObject]]::new()
#endregion default properties

# Set TLS to accept TLS, TLS 1.1 and TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = @(
    [Net.SecurityProtocolType]::Tls
    [Net.SecurityProtocolType]::Tls11
    [Net.SecurityProtocolType]::Tls12
)

#region functions
#Primary Email and UPN Generation
function New-UserPrincipalName {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory)]
        [object]
        $person,

        [Parameter(Mandatory)]
        [string]
        $domain,

        [Parameter(Mandatory)]
        [int]
        $Iteration
    )

    Process {
        try {
            if ($Iteration -eq 0) {
                $suffix = ""
            }
            else {
                $suffix = "$($Iteration)"
            }

            #Check Nickname
            if ([string]::IsNullOrEmpty($person.Name.Nickname)) {
                $FirstName = $person.Name.GivenName
            }
            else {
                $FirstName = $person.Name.Nickname
            }

            if ($person.name.convention.substring(0,1) -eq "P") {
                # PartnerName
                $SurName = "$($person.name.FamilyNamePartnerPrefix) $($person.name.FamilyNamePartner)".Trim()
            }
            else {
                # FamilyName
                $SurName = "$($person.name.FamilyNamePrefix) $($person.name.FamilyName)".Trim()
            }

            $result = ("{0}{1}@{2}" -f $FirstName, $SurName, $domain).toLower().replace("'", "").replace("\s", "")

            Remove-StringLatinCharacters($result)
        }
        catch {
            throw("An error was found in the name convention algorithm: $($_.Exception.Message): $($_.ScriptStackTrace)")
        }
    }
}


function Find-UserPrincipalName {
    [cmdletbinding()]
    Param (
        [Parameter(Mandatory)]
        [object]
        $Person,

        [Parameter(Mandatory)]
        [string]
        $Domain,

        [Parameter(Mandatory)]
        [Object]
        $Headers
    )

    Process {
        $Unique = $False
        $Iteration = 0

        while ($Unique -eq $False) {
            $userPrincipalName = New-UserPrincipalName -person $Person -domain $Domain -Iteration $Iteration

            $splatParams = @{
                Uri     = "$($config.BaseUrl)/Users?filter=startswith(userPrincipalName,'$userPrincipalName')"
                Method  = 'get'
                Headers = $Headers
            }
            $userResponse = Invoke-RestMethod @splatParams

            if ($userResponse.count -eq 0) {
                Write-Verbose -Verbose "$userPrincipalName is uniek"
                $unique = $true
            }
            else {
                Write-Verbose -Verbose "$userPrincipalName is niet uniek"
                $iteration++
            }
        }

        Write-Output $userPrincipalName
    }
}


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


function Remove-StringLatinCharacters {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [string]
        $String
    )

    process {
        [Text.Encoding]::ASCII.GetString(
            [Text.Encoding]::GetEncoding("Cyrillic").GetBytes($String)
        )
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
    givenName                = $p.Name.NickName
    surName                  = Get-SurName $p
    userPrincipalName        = $null # set to null to let the script render a upn based on the Find-UserPrincipalName function
    displayName              = Get-DisplayName $p
    changePasswordNextSignIn = $True
    usageLocation            = "NL"
    preferredLanguage        = "nl"

    employeeId               = $p.ExternalId
    officeLocation           = $p.PrimaryContract.Department.DisplayName
    department               = $p.PrimaryContract.Department.DisplayName
    jobTitle                 = $p.PrimaryContract.Title.Name
    companyName              = $p.PrimaryContract.Organization.Name
    businessPhones           = @("$($p.Contact.Business.Phone.Mobile)")
    mail                     = $null # set to null to match to userPrincipalName, force string to leave empty
    password                 = ''
}

$Success = $False

# Start Script
try {
    Write-Verbose "Getting accessToken"

    $splatGetTokenParams = @{
        TenantId     = $Config.TenantId
        ClientId     = $Config.ClientId
        ClientSecret = $Config.ClientSecret
        Scope        = $Config.Scope
    }
    $accessToken = (Get-LisaAccessToken @splatGetTokenParams).access_token

    $authorizationHeaders = [System.Collections.Generic.Dictionary[[String], [String]]]::new()
    $authorizationHeaders.Add("Authorization", "Bearer $($accessToken)")
    $authorizationHeaders.Add("Content-Type", "application/json")
    $authorizationHeaders.Add("Mwp-Api-Version", "1.0")

    # Create user
    $Filter = "EmployeeID+eq+'$($p.ExternalId)'"

    $splatParams = @{
        Uri     = "$($Config.BaseUrl)/Users?filter=$($Filter)"
        Method  = 'Get'
        Headers = $authorizationHeaders
    }
    $userResponse = Invoke-RestMethod @splatParams

    if ($userResponse.count -gt 1) {
        throw "Multiple accounts found with filter: $($Filter)"
    }

    # Create KPN Lisa Account
    if ($userResponse.count -eq 0) {

        Write-Verbose "Creating KPN Lisa account for '$($p.DisplayName)'"

        # if there is no UPN, we will render it
        if ($null -eq $Account.userPrincipalName) {
            $Account.userPrincipalName = Find-UserPrincipalName -Person $p -Domain $Config.Domain -Headers $authorizationHeaders
        }

        if ($Account.ContainsKey("mail") -and $null -eq $Account.mail) {
            $Account.mail = $Account.userPrincipalName
        }

        $Body = $Account | Select-Object @(
            'changePasswordNextSignIn', 'usageLocation', 'preferredLanguage',
            'givenName', 'surName', 'displayName', 'userPrincipalName'
        )

        $splatParams = @{
            Uri     = "$($Config.BaseUrl)/Users"
            Method  = 'Post'
            Body    = $Body | ConvertTo-Json
            Headers = $authorizationHeaders
        }

        if (-not($dryRun -eq $true)) {
            $userResponse = Invoke-RestMethod @splatParams

            $aRef = $($userResponse.objectId)
            $account.password = $($userResponse.temporaryPassword)
        }
        else {
            write-verbose -verbose $splatParams.body

            $aRef = 'FakeRef'
            $account.password = "FakePassword"
        }

        #Update the user with all other props
        $Body = $Account | Select-Object -Property *, 'accountEnabled' -ExcludeProperty @(
            'changePasswordNextSignIn', 'usageLocation', 'preferredLanguage',
            'givenName', 'surName', 'displayName', 'userPrincipalName',
            'password'
        )

        # Force the account disabled
        $body.accountEnabled = $False

        $splatParams = @{
            Uri     = "$($config.BaseUrl)/Users/$($aRef)/bulk"
            Method  = 'Patch'
            Headers = $authorizationHeaders
            Body    = $Body | ConvertTo-Json
        }

        if (-not($dryRun -eq $true)) {
            [void] (Invoke-RestMethod @splatParams)
        }
        else {
            write-verbose -verbose $splatParams.Body
        }

        # Set the manager
        if ($mRef) {
            $splatParams = @{
                Uri     = "$($Config.BaseUrl)/Users/$($aRef)/Manager"
                Method  = 'Put'
                Body    = ($mRef | ConvertTo-Json)
                Headers = $authorizationHeaders
            }

            if (-not($dryRun -eq $true)) {
                [void] (Invoke-RestMethod @splatParams)
            }

            Write-Verbose "Added Manager $($managerResponse.Value.displayName) to '$($p.DisplayName)'" -Verbose
        }

        $Success = $true

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "CreateAccount" # Optionally specify a different action for this audit log
                Message = "Created account for '$($p.DisplayName)'. Id: $($aRef)"
                IsError = $False
            })

    }
    # Correlate KPN Lisa Account
    else {

        Write-Verbose "Correlating KPN Lisa account for '$($p.DisplayName)'"

        $userResponse = $userResponse.value
        $aRef = $userResponse.id

        #region removable when the correlated flag is available

        $Account.userPrincipalName = $userResponse.userPrincipalName

        if ($Account.ContainsKey("mail")) {
            $Account.mail = $userResponse.mail
        }

        $Body = $Account | Select-Object -Property * -ExcludeProperty @(
            'changePasswordNextSignIn', 'usageLocation', 'preferredLanguage',
            'userPrincipalName', 'password', 'accountEnabled', 'mail'
        )
        $splatParams = @{
            Uri     = "$($config.BaseUrl)/Users/$($aRef)/bulk"
            Method  = 'Patch'
            Headers = $authorizationHeaders
            body    =$Body | ConvertTo-Json
        }

        if (-not($dryRun -eq $true)) {
            [void] (Invoke-RestMethod @splatParams)
        }
        else {
            Write-verbose -verbose $splatParams.Body
        }

        # Set the manager
        if ($mRef) {
            $splatParams = @{
                Uri     = "$($Config.BaseUrl)/Users/$($aRef)/Manager"
                Method  = 'Put'
                Body    = ($mRef | ConvertTo-Json)
                Headers = $authorizationHeaders
            }

            if (-not($dryRun -eq $true)) {
                [void] (Invoke-RestMethod @splatParams)
            }

            Write-Verbose "Added Manager $($managerResponse.Value.displayName) to '$($p.DisplayName)'" -Verbose
        }
        #endregion

        $AuditLogs.Add([PSCustomObject]@{
                Action  = "UpdateAccount" # Optionally specify a different action for this audit log
                Message = "Updated account for '$($p.DisplayName)'. Id: $($aRef)"
                IsError = $False
            })
        $Success = $true
    }
}
catch {
    $ex = $PSItem
    $errorMessage = Get-ErrorMessage -ErrorObject $ex

    Write-Verbose "Error at Line [$($ex.InvocationInfo.ScriptLineNumber)]: $($ex.InvocationInfo.Line). Error: $($errorMessage.VerboseErrorMessage) [$($ex.ErrorDetails.Message)]"

    $auditLogs.Add([PSCustomObject]@{
            Action  = "CreateAccount" # Optionally specify a different action for this audit log
            Message = "Error creating account [$($account.DisplayName)]. Error Message: $($errorMessage.AuditErrorMessage)."
            IsError = $True
        })
}


$result = [PSCustomObject]@{
    Success          = $Success
    AccountReference = $aRef
    AuditLogs        = $AuditLogs
    Account          = $account

    # Optionally return data for use in other systems
    ExportData      = [PSCustomObject]@{
        AccountReference  = $aRef
        userPrincipalName = $Account.userPrincipalName
        employeeId        = $Account.employeeId
        displayName       = $Account.displayName
        mail              = $Account.mail
    }
}

Write-Output $result | ConvertTo-Json -Depth 10
