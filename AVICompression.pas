unit AVICompression;

{ MeeSoft AVI compression unit
  Michael Vinther 1999

  d973971@iae.dtu.dk
  solohome.cjb.net

  See MM.HLP (supplied with Delphi) for help on AVI streams

  Notes on AVIFileOptions.Handler:

  'CVID' = Cinepak Codec of Radius
  'MSVC' = Microsoft Video 1
  'IV32' = Intel Indeo Video 3.2
  'IV50' = Intel Indeo Video 5.0 (Some kind of MPEG, i think. Width and Height must be divisible by 4)
}

interface

 uses Graphics, AVIFile32, Windows, Classes, Forms;

 type
  TAVIFileOptions = object
                     Width, Height  : Integer;
                     Handler        : string[4];
                     Quality        : Integer;
                     FrameRate      : Integer;
                     Name           : string[63];
                     KeyFrameEvery  : Integer;
                     BytesPerSecond : Integer;
                     Flags          : Integer;
                     Compress       : Boolean;
                     ShowDialog     : Boolean;
                     procedure Init;
                    end;

  TAVICompressor = class
                    private
                     AVIFile : PAVIFile;
                     AVIStream, CompStream : PAVIStream;
                     StreamSize : Integer;
                    public
                     SamplesW, BytesW : Integer;

                     constructor Create;
                     destructor Destroy; override;
                     function Open(Name: string; var Options: TAVIFileOptions): Integer;
                     function Close: Integer;

                     function WriteFrame(Bitmap : PBitmapInfo): Integer;  overload;
                     function WriteFrame(Bitmap : Graphics.TBitmap): Integer;  overload;
                   end;

 type TChar4 = array[0..3] of Char;
 function FourCC(S: ShortString): Integer;

implementation

 var AVIInitCount : Integer;

 function FourCC(S: ShortString): Integer;
 begin
  Move(S[1],Result,4);
 end;

 procedure TAVIFileOptions.Init;
 begin
  Width:=0; Height:=0;
  Handler:='CVID';
  Quality:=50*100;
  FrameRate:=18;
  Name:='';
  KeyFrameEvery:=FrameRate;
  BytesPerSecond:=150*1024;
  Flags:=AVICOMPRESSF_DATARATE or AVICOMPRESSF_KEYFRAMES;
  Compress:=True;
  ShowDialog:=True;
 end;

 constructor TAVICompressor.Create;
 begin
  inherited Create;
  if AVIInitCount=0 then AVIFileInit;
  Inc(AVIInitCount);
  AVIFile:=nil;
  AVIStream:=nil;
  CompStream:=nil;
 end;

 destructor TAVICompressor.Destroy;
 begin
  Close;
  Dec(AVIInitCount);
  if AVIInitCount=0 then AVIFileExit;
  inherited Destroy;
 end;

 function TAVICompressor.Open;
 var
  AVIStreamInfo : TAVIStreamInfo;
  CompOptions   : TAVICompressOptions;
  PCompOptions  : PAVICompressOptions;
  bmiHeader     : TBitmapInfoHeader;
  clsidHandler  : ^TClsID;
 begin
  DeleteFile(@Name[1]);
  Result:=AVIFileOpen(AVIFile,@Name[1],OF_CREATE or OF_WRITE,nil);
  if Result<>0 then begin Close; Exit; end;

  FillChar(bmiHeader,SizeOf(TBitmapInfoHeader),0);
  with bmiHeader do // BITMAPINFOHEADER
  begin
   biSize:=SizeOf(TBitmapInfoHeader);
   biWidth:=Options.Width;
   biHeight:=Options.Height;
   biPlanes:=1;
   biBitCount:=24;
   biCompression:=BI_RGB;
   biSizeImage:=((biWidth*3+3) and $fffffffc)*biHeight;
  end;

  FillChar(AVIStreamInfo,SizeOf(AVIStreamInfo),0);
  with AVIStreamInfo do
  begin
   dwSuggestedBufferSize:=bmiHeader.biSizeImage;
   fccType:=streamtypeVIDEO;
   fccHandler:=FourCC(Options.Handler); // CVID MSVC IV32 IV50
   dwFlags:=0;
   dwScale:=1;
   dwRate:=Options.FrameRate;
   dwStart:=0;
   dwLength:=1;
   dwQuality:=Options.Quality;
   dwSampleSize:=0;
   rectFrame:=Rect(0,0,Options.Width-1,Options.Height-1);
   Move(Options.Name[1],szName,63); szName[63]:=#0;
  end;
  Result:=AVIFileCreateStream(AVIFile,AVIStream,AVIStreamInfo);
  if Result<>0 then begin Close; Exit; end;

  if Options.Compress then
  begin
   FillChar(CompOptions,SizeOf(CompOptions),0);
   with CompOptions do  // AVICompressOptions
   begin
    fccType:=AVIStreamInfo.fccType;
    fccHandler:=AVIStreamInfo.fccHandler;
    dwKeyFrameEvery:=Options.KeyFrameEvery;
    dwQuality:=AVIStreamInfo.dwQuality;
    dwBytesPerSecond:=Options.BytesPerSecond;
    dwFlags:=Options.Flags;
    lpFormat:=@bmiHeader;
    cbFormat:=SizeOf(TBitmapInfoHeader);
    dwInterleaveEvery := 1;

    if Options.ShowDialog then
    begin
     PCompOptions:=@CompOptions;
     dwFlags:=dwFlags or AVICOMPRESSF_VALID;
     if not AVISaveOptions(Application.Handle,ICMF_CHOOSE_KEYFRAME or ICMF_CHOOSE_DATARATE,1,AVIStream,PCompOptions) then
     begin
      Result:=-1;
      Close;
      DeleteFile(@Name[1]);
      Exit;
     end;
    end;
   end;

   clsidHandler:=nil;
   Result:=AVIMakeCompressedStream(CompStream,AVIStream,CompOptions,clsidHandler^);
   if Result<>0 then begin Close; Exit; end;
  end
  else
  begin
   CompStream:=AVIStream;
   AVIStream:=nil;
  end;
  Result:=AVIStreamSetFormat(CompStream,0,@bmiHeader,SizeOf(TBitmapInfoHeader));
  if Result<>0 then begin Close; Exit; end;

  SamplesW:=0; BytesW:=0;
  StreamSize:=0;
 end;

 function TAVICompressor.WriteFrame(Bitmap: PBitmapInfo): Integer;
 begin
  Result:=AVIStreamWrite(CompStream,StreamSize,1,Pointer(Integer(Bitmap)+SizeOf(TBitmapInfoHeader)),Bitmap^.bmiHeader.biSizeImage,0,@SamplesW,@BytesW);
  Inc(StreamSize);
 end;

 function TAVICompressor.WriteFrame(Bitmap: Graphics.TBitmap): Integer;
 var
    P: Pointer;
    Sze: integer;
 begin
  case Bitmap.PixelFormat of
    pf8bit: Sze := 1;
    pf16bit: Sze := 2;
    pf24bit: Sze := 3;
    pf32bit: Sze := 4;
  end;
  Result:=AVIStreamWrite(CompStream,StreamSize,1,Bitmap.ScanLine[Bitmap.Height-1],Bitmap.Width*Bitmap.Height*Sze,0,@SamplesW,@BytesW);
  Inc(StreamSize);
 end;{}

 function TAVICompressor.Close;
 begin
  Result:=0;
  if CompStream<>nil then Result:=Result or AVIStreamRelease(CompStream); CompStream:=nil;
  if AVIStream<>nil  then Result:=Result or AVIStreamRelease(AVIStream);  AVIStream:=nil;
  if AVIFile<>nil    then Result:=Result or AVIFileRelease(AVIFile);      AVIFile:=nil;
 end;

begin
 AVIInitCount:=0;
end.

