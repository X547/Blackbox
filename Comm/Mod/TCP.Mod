MODULE CommTCP;
(**
	project	= "BlackBox"
	organization	= "www.oberon.ch"
	contributors	= "Oberon microsystems"
	version	= "System/Rsrc/About"
	copyright	= "System/Rsrc/About"
	license	= "Docu/BB-License"
	references	= "see the CommStreams documentation for details on the semantics of this driver module"
	changes	= ""
	issues	= ""

**)

	IMPORT SYSTEM, Winsock, Strings, Dialog, CommStreams;

	CONST
		hostSpecificError = -1;	(* host-specific error codes *)
		INVALID_SOCKET = Winsock.INVALID_SOCKET;
		SOCKET_ERROR = Winsock.SOCKET_ERROR;

	TYPE
		Stream = POINTER TO RECORD (CommStreams.Stream)
			sock: Winsock.SOCKET;	(* socket must be in non-blocking mode, otherwise recv() or send() could block *)
			remoteAdr: CommStreams.Adr	(* remoteAdr # NIL *)
		END;

		Listener = POINTER TO RECORD (CommStreams.Listener)
			sock: Winsock.SOCKET;
			localAdr: CommStreams.Adr	(* localAdr # NIL *)
		END;

	VAR
		winSockInstalled: BOOLEAN;	(* WinSockets API successfully initialized? *)
		debug*: BOOLEAN;


	(* auxiliary procedures *)

	PROCEDURE CopyOfAdrString (a: CommStreams.Adr): CommStreams.Adr;
		VAR b: CommStreams.Adr;
	BEGIN
		NEW(b, LEN(a)); b := a;
		RETURN b
	END CopyOfAdrString;

	PROCEDURE Error (msg: ARRAY OF CHAR; errno: INTEGER);
		VAR s: ARRAY 128 OF CHAR; errnostr: ARRAY 8 OF CHAR;
	BEGIN
		IF debug THEN
			CASE errno OF
			  Winsock.WSASYSNOTREADY: s := "WSASYSNOTREADY, network subsystem is unavailable"
			| Winsock.WSAVERNOTSUPPORTED: s := "WSAVERNOTSUPPORTED, WINSOCK.DLL version out of range"
			| Winsock.WSAEINVAL: s := "WSAEINVAL, invalid argument"
			| Winsock.WSAETIMEDOUT: s := "WSAETIMEDOUT, connection timed out"
			| Winsock.WSAECONNREFUSED: s := "WSAECONNREFUSED, connection refused"
			| Winsock.WSAEADDRNOTAVAIL: s := "WSAEADDRNOTAVAIL, cannot assign requested address"
			ELSE s := "(please look up the error number in the Winsock symbol file and in the Microsoft documentation)"
			END;
			Strings.IntToString(errno, errnostr);
			Dialog.ShowParamMsg("^0: error ^1 (^2)", msg, errnostr, s)
		END
	END Error;

	PROCEDURE IsIPAddress (name: ARRAY OF CHAR): BOOLEAN;
		(* returns TRUE iff name only contains decimal digits and "." characters *)
		VAR i: INTEGER;
	BEGIN
		i := 0; WHILE ("0" <= name[i]) & (name[i] <= "9") OR (name[i] = ".") DO INC(i) END;
		RETURN name[i] = 0X
	END IsIPAddress;

	PROCEDURE ParseAdr (adr: ARRAY OF CHAR; OUT addr: ARRAY OF CHAR; OUT port: INTEGER; OUT ok: BOOLEAN);
		(* parse address specification with syntax addr [ ":" portnumber ] *)
		VAR i, j, res: INTEGER; portstr: ARRAY 16 OF CHAR;
	BEGIN
		i := 0; j := 0; port := 0; ok := TRUE;
		WHILE (adr[i] # 0X) & (adr[i] # ":") DO
			IF j < LEN(addr) - 1 THEN addr[j] := adr[i]; INC(j) END;
			INC(i)
		END;
		ok := i = j;
		addr[j] := 0X;
		IF ok & (adr[i] = ":") THEN
			INC(i); j := 0;
			WHILE adr[i] # 0X DO
				portstr[j] := adr[i]; INC(i);
				IF j < LEN(portstr) - 1 THEN INC(j) END
			END;
			portstr[j] := 0X;
			Strings.StringToInt(portstr, port, res);
			ok := res = 0
		END
	END ParseAdr;

	PROCEDURE ParseLocalAdr (IN adr: ARRAY OF CHAR;
		OUT peername: ARRAY OF CHAR; OUT port: INTEGER; OUT ok: BOOLEAN
	);
		VAR i, res: INTEGER;
	BEGIN
		IF adr = "" THEN
			port := 0; peername := ""; ok := TRUE	(* default port number 0 means 'don't care which port is used' *)
		ELSE
			i := 0;
			WHILE (adr[i] # 0X) & ((adr[i] >= "0") & (adr[i] <= "9")) OR (adr[i] = " ") DO INC(i) END;
			IF adr[i] # 0X THEN ParseAdr(adr, peername, port, ok)
			ELSE Strings.StringToInt(adr, port, res); peername := ""; ok := res = 0
			END
		END
	END ParseLocalAdr;

	PROCEDURE NameToAdr (IN peername: ARRAY OF CHAR; VAR inaddr: Winsock.in_addr; OUT ok: BOOLEAN);
		VAR hostentry: Winsock.hostentPtr; shortPName: ARRAY 64 OF SHORTCHAR;
	BEGIN
		shortPName := SHORT(peername$);
		IF IsIPAddress(peername) THEN
			inaddr.S_un.S_addr := Winsock.inet_addr(shortPName);
			ok := inaddr.S_un.S_addr # Winsock.INADDR_NONE
		ELSE
			hostentry := Winsock.gethostbyname(shortPName);
			ok := hostentry # NIL;
			IF ok THEN
				inaddr := hostentry.h_addr_list^[0]^[0]
			ELSE
				Error("gethostbyname()", Winsock.WSAGetLastError())
			END
		END
	END NameToAdr;

	PROCEDURE MakeAdr (adr: Winsock.sockaddr_in; OUT s: CommStreams.Adr);
		VAR ipadr, n: INTEGER; temp, buf: ARRAY 64 OF CHAR;
	BEGIN
		ipadr := adr.sin_addr.S_un.S_addr; temp := "";
		IF ipadr # 0 THEN
			n := ipadr MOD 256;
			Strings.IntToString(n, temp);
			n := SYSTEM.LSH(ipadr, -8); n := n MOD 256;
			Strings.IntToString(n, buf); temp := temp + "."+ buf;
			n := SYSTEM.LSH(ipadr, -16); n := n MOD 256;
			Strings.IntToString(n, buf); temp := temp + "."+ buf;
			n := SYSTEM.LSH(ipadr, -24); n := n MOD 256;
			Strings.IntToString(n, buf); temp := temp + "." + buf + ":"
		END;
		n := (adr.sin_port MOD 256) * 256 + (adr.sin_port DIV 256) MOD 256;
		Strings.IntToString(n, buf); temp := temp + buf;
		NEW(s, LEN(temp$) + 1); s^ := temp$
	END MakeAdr;

	PROCEDURE MakeFdSet (socket: Winsock.SOCKET; OUT set: Winsock.fd_set);
	BEGIN
		set.fd_count := 1; set.fd_array[0] := socket
	END MakeFdSet;

	(* Listener *)

	PROCEDURE (l: Listener) LocalAdr (): CommStreams.Adr;
	BEGIN
		RETURN CopyOfAdrString(l.localAdr)
	END LocalAdr;

	PROCEDURE (l: Listener) Accept (OUT s: CommStreams.Stream);
		VAR timeout: Winsock.timeval; set: Winsock.fd_set; res, namelen: INTEGER;
			sock: Winsock.SOCKET; tcpstream: Stream;
			inadr: Winsock.sockaddr_in;
	BEGIN
		timeout.tv_sec := 0; timeout.tv_usec := 0;
		MakeFdSet(l.sock, set);
		res := Winsock.select(0, set, NIL, NIL, timeout);
		ASSERT(res # SOCKET_ERROR, 100);
		IF res > 0 THEN
			namelen := SIZE(Winsock.sockaddr_in);
			sock := Winsock.accept(l.sock, inadr, namelen);
			ASSERT(sock # INVALID_SOCKET, 101);
			namelen := 1;	(* = 'true' *)
			res := Winsock.ioctlsocket(sock, Winsock.FIONBIO, namelen);	(* set to non-blocking mode *)
			ASSERT(res = 0, 102);
			NEW(tcpstream); tcpstream.sock := sock;
			MakeAdr(inadr, tcpstream.remoteAdr);
			s := tcpstream
		END
	END Accept;

	PROCEDURE (l: Listener) Close;
		VAR res: INTEGER;
	BEGIN
		IF l.sock # INVALID_SOCKET THEN
			res := Winsock.closesocket(l.sock);
			l.sock := INVALID_SOCKET
		END
	END Close;

	PROCEDURE (l: Listener) FINALIZE-;
	BEGIN
		WITH l: Listener DO
			IF l.sock # INVALID_SOCKET THEN
				l.Close
			END
		END
	END FINALIZE;

	PROCEDURE NewListener* (localAdr: ARRAY OF CHAR; OUT l: CommStreams.Listener; OUT res: INTEGER);
		(* localAdr must contain a port number *)
		CONST SOMAXCONN = 5;	(* use default length of listener backlog queue *)
		VAR portnr, namelen: INTEGER; ok: BOOLEAN; tcplistener: Listener;
			adr: Winsock.sockaddr_in; sock: Winsock.SOCKET;
			peername: ARRAY 64 OF CHAR;
	BEGIN
		l := NIL;
		IF winSockInstalled THEN
			ParseLocalAdr(localAdr, peername, portnr, ok);
			IF ok & (portnr >= 0) THEN	(* only non-negative port numbers are legal *)
				sock := Winsock.socket(Winsock.PF_INET, Winsock.SOCK_STREAM, Winsock.IPPROTO_TCP);
				ASSERT(sock # INVALID_SOCKET, 100);
				adr.sin_family := Winsock.PF_INET;
				adr.sin_port := Winsock.htons(SHORT(portnr));
				NameToAdr(peername, adr.sin_addr, ok);
				IF ok THEN
					res := Winsock.bind(sock, adr, SIZE(Winsock.sockaddr_in));
					IF res = 0 THEN
						res := Winsock.listen(sock, SOMAXCONN);
						ASSERT(res = 0, 102);
						NEW(tcplistener); tcplistener.sock := sock;
						namelen := SIZE(Winsock.sockaddr_in);
						res := Winsock.getsockname(sock, adr, namelen);
						ASSERT(res = 0, 103);
						MakeAdr(adr, tcplistener.localAdr);
						l := tcplistener;
						res := CommStreams.done
					ELSE 
						res := CommStreams.localAdrInUse
					END
				ELSE
					res := Winsock.closesocket(sock);
					res := CommStreams.invalidLocalAdr
				END
			ELSE 
				res := CommStreams.invalidLocalAdr
			END
		ELSE
			res := CommStreams.networkDown
		END
	END NewListener;


	(* Stream *)

	PROCEDURE (s: Stream) RemoteAdr (): CommStreams.Adr;
	BEGIN
		RETURN CopyOfAdrString(s.remoteAdr)
	END RemoteAdr;

	PROCEDURE (s: Stream) IsConnected (): BOOLEAN;
		(* Give an educated guess on whether the peer has closed the connection. *)
		(* This is not a guarantee that data sent on s will arrive at the peer. *)
		VAR timeout: Winsock.timeval; set: Winsock.fd_set; n, res, avail: INTEGER;
	BEGIN
		IF s.sock = INVALID_SOCKET THEN
			RETURN FALSE
		ELSE
			timeout.tv_sec := 0; timeout.tv_usec := 0;
			MakeFdSet(s.sock, set);
			n := Winsock.select(0, set, NIL, NIL, timeout);
			ASSERT(n # SOCKET_ERROR, 100);
			IF n = 1 THEN	(* a recv on s.sock would not block; find out whether there is data queued *)
				res := Winsock.ioctlsocket(s.sock, Winsock.FIONREAD, avail);
				ASSERT(res = 0, 101);
				(* if there is data queued, we assume the socket is still open.
					if no data is queued, then we know that a recv can only return with zero bytes
					read, telling us that the socket has been closed. *)
				RETURN avail > 0
			ELSE (* a recv on s.sock would block, so the peer has not closed the socket yet or the connect failed entirely *)
				timeout.tv_sec := 0; timeout.tv_usec := 0;
				MakeFdSet(s.sock, set);
				n := Winsock.select(0, NIL, NIL, set, timeout);
				ASSERT(n # SOCKET_ERROR, 102);
				IF n = 1 THEN s.Close END;
				RETURN n = 0
			END
		END
	END IsConnected;

	PROCEDURE (s: Stream) WriteBytes (IN x: ARRAY OF BYTE; beg, len: INTEGER; OUT written: INTEGER);
		VAR res: INTEGER;
	BEGIN
		ASSERT(beg >= 0, 20);
		ASSERT(len > 0, 21);
		ASSERT(LEN(x) >= beg + len, 22);
		written := Winsock.send(s.sock, SYSTEM.ADR(x) + beg, len, {});
		IF written = SOCKET_ERROR THEN
			res := Winsock.WSAGetLastError();
			IF (res # Winsock.WSAEWOULDBLOCK) & (res # Winsock.WSAENOTCONN) THEN Error("send()", res) END;
			written := 0
		END
	END WriteBytes;

	PROCEDURE (s: Stream) ReadBytes (VAR x: ARRAY OF BYTE; beg, len: INTEGER; OUT read: INTEGER);
		VAR res: INTEGER;
	BEGIN
		ASSERT(beg >= 0, 20);
		ASSERT(len > 0, 21);
		ASSERT(LEN(x) >= beg + len, 22);
		read := Winsock.recv(s.sock, SYSTEM.ADR(x) + beg, len, {});
		IF read = SOCKET_ERROR THEN
			res := Winsock.WSAGetLastError();
			IF (res = Winsock.WSAEWOULDBLOCK) OR (res = Winsock.WSAENOTCONN) THEN
				read := 0	 (* there is nothing to be read *)
			ELSIF res = Winsock.WSAECONNRESET THEN
				read := 0;
				s.Close	(* prevent trap *)
			ELSE
				Error("recv()", res);
				read := 0; s.Close
			END
		END
	END ReadBytes;

	PROCEDURE (s: Stream) Close;
		VAR res: INTEGER;
	BEGIN
		res := Winsock.closesocket(s.sock);
		s.sock := INVALID_SOCKET
	END Close;

	PROCEDURE (s: Stream) FINALIZE-;
	BEGIN
		IF s.sock # INVALID_SOCKET THEN
			s.Close
		END
	END FINALIZE;

	PROCEDURE CreateStream (
		OUT s: CommStreams.Stream; sock: Winsock.SOCKET; IN remoteAdr: ARRAY OF CHAR
	);
		VAR stream: Stream;
	BEGIN
		NEW(stream); stream.sock := sock;
		NEW(stream.remoteAdr, LEN(remoteAdr$)+1); stream.remoteAdr^ := remoteAdr$;
		s := stream
	END CreateStream;

	PROCEDURE NewStream* (
		localAdr, remoteAdr: ARRAY OF CHAR; OUT s: CommStreams.Stream; OUT res: INTEGER
	);
		(* localAdr may contain a port number *)
		(* remoteAdr must contain an address in the format  ( ip-address | hostname ) [ ":" portnumber ] *)
		VAR adr: Winsock.sockaddr_in;
			rpeername, lpeername: ARRAY 64 OF CHAR;
			inaddr: Winsock.in_addr; lport, rport: INTEGER; ok: BOOLEAN;
			sock: Winsock.SOCKET;
	BEGIN
		s := NIL;
		IF winSockInstalled THEN
			ParseAdr(remoteAdr, rpeername, rport, ok);
			IF ok THEN
				sock := Winsock.socket(Winsock.PF_INET, Winsock.SOCK_STREAM, Winsock.IPPROTO_TCP);
				IF sock # INVALID_SOCKET THEN
					ParseLocalAdr(localAdr, lpeername, lport, ok);
					IF ok & (lport >= 0) THEN	(* only non-negative port numbers are legal *)
						adr.sin_family := Winsock.PF_INET;
						adr.sin_port := Winsock.htons(SHORT(lport));
						NameToAdr(lpeername, adr.sin_addr, ok);
						res := Winsock.bind(sock, adr, SIZE(Winsock.sockaddr_in));
						IF res = 0 THEN
							NameToAdr(rpeername, inaddr, ok);
							IF ok THEN
								adr.sin_family := Winsock.PF_INET;
								adr.sin_port := Winsock.htons(SHORT(rport));
								adr.sin_addr := inaddr;
								res := 1;	(* = 'true' *)
								res := Winsock.ioctlsocket(sock, Winsock.FIONBIO, res);	(* set to non-blocking mode *)
								ASSERT(res = 0, 101);
								res := Winsock.connect(sock, adr, SIZE(Winsock.sockaddr_in));
								IF res = 0 THEN
									CreateStream(s, sock, remoteAdr); res := CommStreams.done
								ELSE
									res := Winsock.WSAGetLastError();
									IF res = Winsock.WSAEWOULDBLOCK THEN
										CreateStream(s, sock, remoteAdr); res := CommStreams.done
									ELSE
										Error("connect()", res);
										res := Winsock.closesocket(sock);
										res := hostSpecificError
									END
								END
							ELSE
								res := Winsock.closesocket(sock);
								res := CommStreams.invalidRemoteAdr
							END
						ELSE
							res := Winsock.closesocket(sock);
							res := CommStreams.invalidLocalAdr
						END
					ELSE
						res := CommStreams.invalidLocalAdr
					END
				ELSE
					Error("socket()", Winsock.WSAGetLastError());
					res := hostSpecificError
				END
			ELSE
				res := CommStreams.invalidRemoteAdr
			END
		ELSE
			res := CommStreams.networkDown
		END
	END NewStream;

	PROCEDURE Init;
		CONST version = 00000101H;
		VAR data: Winsock.WSADATA; ret: INTEGER;
	BEGIN
		debug := TRUE;
		winSockInstalled := FALSE;
		ret := Winsock.WSAStartup(version, data);
		IF ret = 0 THEN
			winSockInstalled := TRUE
		ELSE
			Error("WSAStartup()", ret)
		END;
		debug := FALSE
	END Init;

	PROCEDURE Close;
		VAR ret: INTEGER;
	BEGIN
		ret := Winsock.WSACleanup()
	END Close;

BEGIN
	Init
CLOSE
	Close
END CommTCP.
