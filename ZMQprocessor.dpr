program ZMQprocessor;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils, System.AnsiStrings, System.Hash, Variants, zmq, zmqapi, superobject,
  dm in 'dm.pas' {dmPG: TDataModule};

var
  host, portPub, portSub: AnsiString;
  dbhost, dbport, dbname, dbuser, dbpwd: string;
  i, user_id: integer;
  context: TZMQContext;
  subscriber, translator: TZMQSocket;
  filter, content: UTF8String;
  contentW: widestring;
  jsonObj: ISuperObject;
  sendStr: AnsiString;
  msgType, msgEmail, msgPwd, msgMsg_id: AnsiString;
  dmPG: TdmPG;
  LoginSuccess: boolean;

begin
  try
    // Считывание параметров командной строки
    i := 1;
    while i<=ParamCount do begin
      if AnsiCompareText(ParamStr(i), 'broker-host')=0 then begin
        host := ParamStr(i+1);
        inc(i);
      end else if AnsiCompareText(ParamStr(i), 'pub')=0 then begin
        portPub := ParamStr(i+1);
        inc(i);
      end else if AnsiCompareText(ParamStr(i), 'sub')=0 then begin
        portSub := ParamStr(i+1);
        inc(i);
      end else if AnsiCompareText(ParamStr(i), 'db-host')=0 then begin
        dbhost := ParamStr(i+1);
        inc(i);
      end else if AnsiCompareText(ParamStr(i), 'db-port')=0 then begin
        dbport := ParamStr(i+1);
        inc(i);
      end else if AnsiCompareText(ParamStr(i), 'db-name')=0 then begin
        dbname := ParamStr(i+1);
        inc(i);
      end else if AnsiCompareText(ParamStr(i), 'db-user')=0 then begin
        dbuser := ParamStr(i+1);
        inc(i);
      end else if AnsiCompareText(ParamStr(i), 'db-pwd')=0 then begin
        dbpwd := ParamStr(i+1);
        inc(i);
      end;
      inc(i);
    end;

    context := TZMQContext.create;
    try
      // Получение входящего сообщения
      subscriber := context.Socket(stSub);
      try
        subscriber.connect('tcp://'+host+':'+portSub);
        subscriber.Subscribe('api_in');
        subscriber.recv(filter);
        subscriber.recv(content);

        // Библиотека superobject работает в widestring, поэтому тут конвертация из UTF8
        contentW := UTF8ToWideString(content);

        jsonObj := SO(contentW);
        try
          msgType  := jsonObj.S['type'];
          msgEmail := jsonObj.S['email'];
          msgPwd   := jsonObj.S['pwd'];
          msgMsg_id := jsonObj.S['msg_id'];
        finally
          jsonObj := nil;
        end;
      finally
        subscriber.Free;
      end;

      if System.AnsiStrings.AnsiCompareText(msgType, 'login')<>0 then Exit;

      jsonObj := SO;

      if (msgType='') or (msgEmail='') or (msgPwd='') or (msgMsg_id='') then begin
        // Если тип ошибки "нет одного из полей или поля пустые" относится ко входному сообщению
        jsonObj.S['msg_id'] := msgMsg_id;
        jsonObj.S['status'] := 'error';
        jsonObj.S['error']  := 'WRONG_FORMAT';
      end else begin
        // Проверки на наличие полей? Проверка чтобы passw и user_id были непустые? WRONG_FORMAT ?
        LoginSuccess := False;
        dmPG := TdmPG.Create(nil);
        try
          dmPG.fdConn.Params.Add('Server='+dbhost);
          dmPG.fdConn.Params.Add('Port='+dbport);
          dmPG.fdConn.Params.Database := dbname;
          dmPG.fdConn.Params.UserName := dbuser;
          dmPG.fdConn.Params.Password := dbpwd;
          dmPG.fdConn.Connected := True;
          dmPG.fdQuery.ParamByName('EMAIL').Value := msgEmail;
          dmPG.fdQuery.Open;
          if not dmPG.fdQuery.IsEmpty then
            if not VarIsNull(dmPG.fdQuery['passw']) then                      // Пустое поле passw - это WRONG_FORMAT ?
              if dmPG.fdQuery['passw']=System.Hash.THashMD5.GetHashString(msgPwd) then begin
                if not VarIsNull(dmPG.fdQuery['user_id']) then begin          // Пустое поле user_id - это WRONG_FORMAT ?
                  user_id := dmPG.fdQuery['user_id'];
                  LoginSuccess := True;
                end;
              end;
        finally
          dmPG.Free;
        end;

        if LoginSuccess then begin
          jsonObj.S['msg_id']  := msgMsg_id;
          jsonObj.I['user_id'] := user_id;
          jsonObj.S['status']  := 'ok';
        end else begin
          jsonObj.S['msg_id'] := msgMsg_id;
          jsonObj.S['status'] := 'ok';
          jsonObj.S['error']  := 'WRONG_PWD';
        end;
      end;

      // Отправка исходящего сообщения
      translator := context.Socket(stPub);
      try
        sendStr := jsonObj.AsJSon;
        translator.bind('tcp://'+host+':'+portPub);
        translator.send(['api_out', sendStr]);
      finally
        translator.Free;
      end;

    finally
      Writeln('context.Free');
      context.Free;
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.

