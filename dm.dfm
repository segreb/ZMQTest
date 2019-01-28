object dmPG: TdmPG
  OldCreateOrder = False
  Height = 150
  Width = 215
  object fdConn: TFDConnection
    Params.Strings = (
      'Database=postgres'
      'User_Name=postgres'
      'Password=postgres'
      'DriverID=PG')
    LoginPrompt = False
    Left = 24
    Top = 16
  end
  object fdQuery: TFDQuery
    Connection = fdConn
    SQL.Strings = (
      'select * from public."user" where email=:email')
    Left = 96
    Top = 16
    ParamData = <
      item
        Name = 'EMAIL'
        ParamType = ptInput
      end>
  end
end
