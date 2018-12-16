module WhiteSpace 		
  DEFAULTVER="0.3" 	 	 
  SUPPORTEDVER="0.4" 	    	
  OPS={ 		  	 	
    :push  => { :ver => '0.2', :imp => 's',  :command => 's',  :parameter => { :int => :any   } },
    :dup   => { :ver => '0.2', :imp => 's',  :command => 'ns', },
    :copy  => { :ver => '0.3', :imp => 's',  :command => 'ts', :parameter => { :int => :fail_on_negative } },
    :swap  => { :ver => '0.2', :imp => 's',  :command => 'nt', },
    :pop   => { :ver => '0.2', :imp => 's',  :command => 'nn', },
    :slide => { :ver => '0.3', :imp => 's',  :command => 'tn', :parameter => { :int => :nop_on_nonpositive } },
    :permr => { :ver => '0.4', :imp => 's',  :command => 'tts', },
    :add   => { :ver => '0.2', :imp => 'ts', :command => 'ss', },
    :sub   => { :ver => '0.2', :imp => 'ts', :command => 'st', },
    :mul   => { :ver => '0.2', :imp => 'ts', :command => 'sn', },
    :div   => { :ver => '0.2', :imp => 'ts', :command => 'ts', },
    :mod   => { :ver => '0.2', :imp => 'ts', :command => 'tt', },
    :stor  => { :ver => '0.2', :imp => 'tt', :command => 's',  },
    :retr  => { :ver => '0.2', :imp => 'tt', :command => 't',  },
    :mark  => { :ver => '0.2', :imp => 'n',  :command => 'ss', :parameter => { :label => :register } },
    :call  => { :ver => '0.2', :imp => 'n',  :command => 'st', :parameter => { :label => :refer } },
    :jump  => { :ver => '0.2', :imp => 'n',  :command => 'sn', :parameter => { :label => :refer } },
    :jzero => { :ver => '0.2', :imp => 'n',  :command => 'ts', :parameter => { :label => :refer } },
    :jneg  => { :ver => '0.2', :imp => 'n',  :command => 'tt', :parameter => { :label => :refer } },
    :ret   => { :ver => '0.2', :imp => 'n',  :command => 'tn', },
    :end   => { :ver => '0.2', :imp => 'n',  :command => 'nn', },
    :putc  => { :ver => '0.2', :imp => 'tn', :command => 'ss', },
    :puti  => { :ver => '0.2', :imp => 'tn', :command => 'st', },
    :getc  => { :ver => '0.2', :imp => 'tn', :command => 'ts', },
    :geti  => { :ver => '0.2', :imp => 'tn', :command => 'tt', },
  } 		   		
  DOPS={ 		    	
    :dumps => {},
    :dumph => {},
  } 			    
  def self.checkVersion(ver)	 	  		
    raise "unsupported version #{ver}" if ver>SUPPORTEDVER
  end 		  	 	
   
  Code=Struct.new( 			 	  
    :ver, :iset, :rcode, :acode, :info
  ) 		 	  	
  module Common		 	   
    NULLLABEL="null"
    NULLRAW="n"
    PARAMREGEX=/^([-+]?)(\d+)(?:\s*\(\s*(\d+)\s*b\s*\))?$/
    LABELREGEX=/^[a-zA-Z]\w*$/
   
    def self.label2uint(sign,val,len)
      ( ( sign ? 2 : 3 ) << len ) + val - 1
    end
   
    def self.uint2label(uint)
      raise "Unexpected" if uint<0
      return nil if uint==0
      len=(uint+1).bit_length-2
      s,v=(uint+1).divmod(1<<len)
      [s<3,v,len]
    end
   
    def self.val2str(sign,val,len)
      "#{sign ? ?+ : ?-}#{val}(#{len}b)"
    end
   
    def self.val2raw(sign,val,len=nil)
      vstr = val==0 ? "" : val.to_s(2).tr("01","st")
      vl=vstr.size
      len||=vl
      raise "too short length" if len<vl
      raw=(sign ? "s" : "t")+"s"*(len-vl)+vstr+"n"
      [raw,len]
    end
   
    def self.parseRawParam(ptok,islabel)
      raise "unexpected parameter token" if ptok[-1]!="n"||!islabel&&ptok.size<=1
      return [0,NULLLABEL] if islabel&&ptok.size==1
      sign=ptok[0]=="s"
      val=ptok[1..-2].tr("st","01").to_i(2)
      len=ptok.size-2
      pstr=val2str(sign,val,len)
      [ islabel ? label2uint(sign,val,len) : sign ? val : -val, pstr ]
    end
   
    def self.parseParam(tok,islabel)
      if tok==NULLLABEL
        raise "#{NULLLABEL} is allowed only for label" unless islabel
        return ["n",0,NULLLABEL]
      end
      return [nil,nil,tok] if islabel&&LABELREGEX.match(tok)
      m=PARAMREGEX.match(tok) or raise "a wrong parameter '#{tok}' detected"
      _,s,v,l=m.to_a
      s=s!="-"
      v=v.to_i
      raw,l=val2raw(s,v,l&&l.to_i) rescue raise "#{$!} in parameter '#{tok}'"
      islabel ?
        [raw, label2uint(s,v,l), val2str(s,v,l)] :
        [raw, s ? v : -v] 
    end
   
    def self.registerInst(pref,iset,pval,inst,posstr,warn,labels,pstr,refers)
      isym="ws#{inst}".to_sym
      if !pref
        iset.push([isym])
        return
      end
      if irest=pref[:int] # integer
        if irest==:fail_on_negative&&pval<0
          iset.push([:wserr,"negative parameter is not allowed for #{inst}"])
          info[:warn].push("negative parameter with #{inst} at #{posstr} may cause runtime error")
        elsif irest==:nop_on_nonpositive&&pval<=0
          iset.push([:wsnop])
          info[:warn].push("non-positive parameter with #{inst} at #{posstr} has no effect")
        else
          iset.push([isym,pval])
        end
      else # label
        ip=iset.size
        case lrest=pref[:label]
        when :register
          key=pval||pstr
          if lref=labels[key]
            info[:warn].push("duplicate label #{pstr} detected at #{posstr}, ignored")
            lref[0].push(ip)
          else
            labels[key]=[[ip],[],pstr,posstr] # ip to jump to
          end
          iset.push([:wsnop])
        when :refer
          refers[ip]=[pval,pstr,inst,posstr]
          iset.push([isym])
        else
          raise "unexpected"
        end
      end
    end
   
    def self.linkLabel(labels,refers,iset,warn)
      refers.each{|ip,(lval,lstr,inst,posstr)|
        key=lval||lstr
        ref=labels[key]
        if ref&&(jip=ref[0][0])
          iset[ip].push(jip)
        else
          iset[ip][0,2]=[:wserr,"failed to jump to a non-existent label #{lstr}"]
          warn.push("label #{lstr} does not exist for #{inst} at #{posstr}")
          ref||=labels[key]=[[],[],lstr,nil]
        end
        ref[1].push(ip)
      }
      labels.each_value{|rega,refa,lstr,posstr|
        next if !refa.empty?
        warn.push("label #{lstr} registered at #{posstr} but not referrenced")
      }
    end
   
    def self.autoLabel(labels,rcode)
      tlabels=labels.keys.select{|k| String===k }.sort_by{|k|
        lreg,lref=labels[k]
        -lreg.size-lref.size
      }
      lcand=-1
      tlabels.each{|k|
        lref=labels[k]
        nil while labels[lcand+=1]
        raw,vstr=NULLRAW,NULLLABEL
        if ldata=uint2label(lcand)
          raw,=val2raw(*ldata)
          vstr=val2str(*ldata)
        end
        lref[4]=vstr
        0.upto(1){|i|
          lref[i].each{|ip|
            rcode[ip]+=raw
          }
        }
      }
    end
   
    def self.summarize(info,labels,rcode)
      info[:size]={
        inst: rcode.size,
        byte: rcode.reduce(0){|s,r| s+r.size }
      }
      info[:label]=labels.values.map{|rega,refa,vstr,posstr,relabel|
        { label: vstr,
          count: rega.size+refa.size,
          relabel: relabel,
          ip: rega[0],
          pos: posstr, }
      }
    end
  end 	 	 			
   
   
  class Loader	     
    def initialize
      @ptree=OPS.each_with_object({}){|(k,v),h|
        *pre,post=(v[:imp]+v[:command]).chars
        pre.each{|c| h=h[c]||={} }
        h[post]=k
      }
    end
   
    def load(sin,raw: true,ver: DEFAULTVER)
      WhiteSpace::checkVersion(ver)
      ret=Code.new(ver,iset=[],rcode=[],acode=[],info={:pos=>[],:warn=>[]})
      labels={}
      refers={}
      ctab=[]
      (raw ? " \t\n" : "stn").each_byte.with_index{|c,i| ctab[c]="stn"[i] }
      pos,spos=-1
      loop {
        ref,itok,ptok,spos,inst,instr,pref=@ptree,"",""
        while c=sin.getbyte
          pos+=1
          x=ctab[c] or next
          itok << x
          if pref
            ptok << x
            next if x!='n'
            if ptok.size==1 && pref[:int]
              info[:warn].push("a null argument is allowed only as a label ( inst: #{inst}, pos: #{spos} )")
              break
            end
          else
            spos||=pos
            ref=ref[x] or break c=nil
            next if Hash===ref
            instr=OPS[inst=ref]
            pref=instr[:parameter] and next
          end
          info[:pos].push(spos)
          posstr="pos #{spos}"
          if instr[:ver]>ver
            iset.push([:wserr,"unspported instruction #{inst}"])
            info[:warn].push("unspported instruction #{inst} at #{posstr} may cause runtime error")
            break spos=nil
          end
          rcode.push(itok)
          pval,pstr=nil
          if !pref # パラメータ無し
            acode.push(inst.to_s)
          else
            pval,pstr=Common::parseRawParam(ptok,!pref[:int])
            acode.push("#{inst} #{pstr}")
          end
          Common::registerInst(pref,iset,pval,inst,posstr,info[:warn],labels,pstr,refers)
          break true
        end or break
      }
      if spos
        iset.push([:wserr,"invalid code pattern"])
        info[:pos].push(spos)
      end
      Common::linkLabel(labels,refers,iset,info[:warn])
      Common::summarize(info,labels,rcode)
      ret
    end
  end 	 		  
   
  class Assembler		 				
    def load(sin, ver: DEFAULTVER)
      WhiteSpace::checkVersion(ver)
      ret=Code.new(ver,iset=[],rcode=[],acode=[],info={:line=>[],:warn=>[]})
      re=/^(?:\s*(!)?(\w+)(?:\s+([^#\s][^#]*?))?)?(?=\s*(?:#|$))/
      labels={}
      refers={}
      sin.each.with_index(1){|line,lineno|
        posstr="line #{lineno}"
        begin
          m=re.match(line) or raise "an invalid line detected"
          code,df,inst,pstr=m[0,4]
          next unless inst # comment only
          instr=(df ? DOPS : OPS)[inst.to_sym] or
            raise "unknown#{df ? 'debug' : ''} instruction '#{inst}' detected"
          raise "unspported instruction #{inst}" if !df&&instr[:ver]>ver
          acode.push(code)
          info[:line].push(lineno)
          pval,lstr=nil
          if !(pref=instr[:parameter])
            raise "parameters not allowed for instrunction '#{inst}'" if pstr
            rcode.push(df ? "" : instr[:imp]+instr[:command])
          else
            raise "no parameters found for instruction '#{inst}'" if !pstr
            praw,pval,lstr=Common::parseParam(pstr,!pref[:int])
            rcode.push(df ? "" : instr[:imp]+instr[:command]+(praw||""))
          end
          Common::registerInst(pref,iset,pval,inst,posstr,info[:warn],labels,lstr,refers)
        rescue String => err
          raise "#{err} in source at #{posstr}"
        end
      }
      Common::linkLabel(labels,refers,iset,info[:warn])
      Common::autoLabel(labels,rcode)
      Common::summarize(info,labels,rcode)
      ret
    end
   
  end 		 		  
 
  class VM   		  	 	
    Rinfo = Struct.new(
      :step,:lastip,:stacksize,:stackhwm,:heapelems,:haddrmax,:cstackhwm,:error
    )
   
    class Error < StandardError
      def initialize(msg)
        @msg=msg
      end
      attr_reader :msg
    end
    INTLINE_REGEX=/^\s*(-)?\s*(\d+)\s*$/
    DEFAULT_LIMIT={
      :step => 10000000,
      :stacksize => 10000,
      :heapelems => 10000,
      :calldepth => 10000,
    }
    def initialize(code,sin: $stdin,sout: $stdout,limit:{},debug:false)
      @iset,@sin,@sout,@debug=code.iset,sin,sout,debug
      @limit=DEFAULT_LIMIT.each_with_object({}){|(k,v),h|
        h[k]=limit[k]||v
      }
      @ip=0
      @stack=[]
      @stackhwm=0
      @heap={}
      @haddrmax=-1
      @cstack=[]
      @cstackhwm=0
      @step=0
      @debugcnt=0
    end
   
# suplemental methods 
    def checkStackDepth(d=1)
      ssize=@stack.size
      raise Error,"stack empty" if ssize==0
      raise Error,"insufficient stack size" if d>ssize
    end
   
    def updateStackHWM
      ssize=@stack.size
      raise Error,"stack overflow" if ssize>=@limit[:stacksize]
      @stackhwm=ssize+1 if ssize>=@stackhwm
    end
   
    def updateCStackHWM
      cdepth=@cstack.size
      raise Error,"call stack overflow" if cdepth>=@limit[:calldepth]
      @cstackhwm=cdepth+1 if cdepth>=@cstackhwm
    end
   
    def checkDivider(val)
      raise Error,"zero devision occurred" if val==0
    end
   
    def storeHeap(val,addr)
      @heap[addr]=val
      @haddrmax=addr if addr>@haddrmax
      true
    end
   
    def checkHeapAddress(addr,readonly=false)
      raise Error,"minus address for heap is not allowed" if addr<0
      if readonly
        raise Error,"access to unallocated heap area" if addr>@haddrmax
      else
        raise Error,"heap overflow" if !@heap[addr]&&@heap.size>=@limit[:heapelems]
      end
    end
   
    def getCommon
      checkStackDepth
      addr=@stack.pop
      checkHeapAddress(addr)
      val=yield
      storeHeap(val,addr)
    end
   
    def jumpCommon(ip)
      @ip=ip
    end
# instructions  
    def wspush(val)
      updateStackHWM
      @stack.push(val)
      true
    end
   
    def wsdup
      checkStackDepth
      updateStackHWM
      @stack.push(@stack[-1])
      true
    end
   
    def wscopy(pos)
      # pos must be non-negative
      checkStackDepth(pos+1)
      updateStackHWM
      @stack.push(@stack[-1-pos])
      true
    end
   
    def wsswap
      checkStackDepth(2)
      @stack[-2..-1]=@stack[-1],@stack[-2]
      true
    end
   
    def wspop
      checkStackDepth
      @stack.pop
      true
    end
   
    def wsslide(num)
      # num must be positive
      checkStackDepth(num+1)
      tmp=@stack.pop(num+1)
      @stack.push(tmp[-1])
      true
    end
   
    def wspermr
      @stack.shuffle!
      true
    end
   
    def wsadd
      checkStackDepth(2)
      tmp=@stack.pop
      @stack[-1]+=tmp
      true
    end
   
    def wssub
      checkStackDepth(2)
      tmp=@stack.pop
      @stack[-1]-=tmp
      true
    end
   
    def wsmul
      checkStackDepth(2)
      tmp=@stack.pop
      @stack[-1]*=tmp
      true
    end
   
    def wsdiv
      checkStackDepth(2)
      tmp=@stack.pop
      checkDivider(tmp)
      @stack[-1]/=tmp
      true
    end
   
    def wsmod
      checkStackDepth(2)
      tmp=@stack.pop
      checkDivider(tmp)
      @stack[-1]%=tmp
      true
    end
   
    def wsstor
      checkStackDepth(2)
      addr,val=@stack.pop(2)
      checkHeapAddress(addr)
      storeHeap(val,addr)
    end
   
    def wsretr
      checkStackDepth
      addr=@stack.pop
      checkHeapAddress(addr,true)
      @stack.push(@heap[addr]||0)
      true
    end
   
    def wscall(ip)
      updateCStackHWM
      @cstack.push(@ip)
      jumpCommon(ip)
    end
   
    def wsjump(ip)
      jumpCommon(ip)
    end
   
    def wsjzero(ip)
      checkStackDepth
      return true unless @stack.pop==0
      jumpCommon(ip)
    end
   
    def wsjneg(ip)
      checkStackDepth
      return true unless @stack.pop<0
      jumpCommon(ip)
    end
   
    def wsret
      ip=@cstack.pop or raise Error,"call stack empty"
      @ip=ip
      true
    end
   
    def wsend
      false
    end
   
    def wsputc
      checkStackDepth
      @sout.putc(@stack.pop) # mod 256
      true
    end
   
    def wsputi
      checkStackDepth
      @sout.print(@stack.pop) # with no NL
      true
    end
   
    def wsgetc
      getCommon {
        @sin.getbyte or raise Error,"detected end of file"
      }
    end
   
    def wsgeti
      # skip leading spaces/tabs, then get one line and trim trailing spaces/tabs, finally parse to integer
      getCommon {
        line=@sin.gets or raise Error,"detected end of file"
        m=INTLINE_REGEX.match(line) or raise Error,"integer parse failed"
        m.captures.join.to_i
      }
    end
   
    def wsnop
      true
    end
   
    def wserr(msg)
      raise Error,msg
    end
   
    def wsdumps
      return true unless @debug
      @sout.print("\##{@debugcnt}\#")
      $stderr.puts("** debug #{@debugcnt}: stack dump at step #{@step}, ip #{@ip} **")
      $stderr.puts(@stack.to_s)
      @debugcnt+=1
      true
    end
   
    def wsdumph
      return true unless @debug
      @sout.print("\##{@debugcnt}\#")
      $stderr.puts("** debug #{@debugcnt}: heap dump at step #{@step}, ip #{@ip} **")
      $stderr.puts(@heap.to_s)
      @debugcnt+=1
      true
    end
# execution  
    def stepi
      raise Error,"reached the step count limit" if (ls=@limit[:step]) && @step>=ls
      @step+=1
      inst=@iset[@ip] or raise Error,"unexpected end of code"
      __send__(*inst) or return false
      @ip+=1
      true
    end
   
    def run
      r=Rinfo.new
      loop do
        begin
          stepi or break
        rescue Error => e
          break r.error=e.msg
        end
      end
      r.step,r.lastip,r.stacksize,r.stackhwm,r.heapelems,r.haddrmax,r.cstackhwm=
        @step,@ip,@stack.size,@stackhwm,@heap.size,@haddrmax,@cstackhwm
      r
    end
  end 	  	   
end   
   
def optParse(argv)  
  opts={ 
    :noexec => false,
    :disassemble => false,
    :itype => :auto,
    :otype => :raw,
    :assemble => false,
    :reportexec => false,
    :reportcode => false,
    :quiet => false,
    :ifile => nil,
    :ofile => nil,
    :strict => false,
    :stdin => nil,
    :stdout => nil,
    :unlimit => false,
    :version => WhiteSpace::DEFAULTVER,
    :debug => false,
  } 
  oparser=OptionParser.new 
  oparser.on("-n","--noexec","Don't execute") {|v|
    opts[:noexec]=v
  } 
  oparser.on("-D","--disassemble","Dissassemble source") {|v|
    opts[:disassemble]=v
  } 
  oparser.on("-t","--itype TYPE",[:auto,:raw,:stn,:wss],"Source code type(default: auto)") {|v|
    opts[:itype]=v
  } 
  oparser.on("-T","--otype TYPE",[:raw,:stn],"Dissasembled source code type(default: raw)") {|v|
    opts[:otype]=v
  } 
  oparser.on("-S","--assemble","Assemble source") {|v|
    opts[:assemble]=v
  } 
  oparser.on("-r","--report-exec","Report execution details") {|v|
    opts[:reportexec]=v
  } 
  oparser.on("-R","--report-code","Report code details") {|v|
    opts[:reportcode]=v
  } 
  oparser.on("-q","--quiet","Do not output warnings") {|v|
    opts[:quiet]=v
  } 
  oparser.on("-o","--outfile FILENAME","File to save assembled/disassembled source") {|v|
    opts[:ofile]=v
  } 
  oparser.on("--strict","Abort immediately on warnings"){|v|
    opts[:strict]=v
  } 
  oparser.on("--stdin FILE","Input file for STDIN"){|v|
    opts[:stdin]=v
  } 
  oparser.on("--stdout FILE","Output file for STDOUT"){|v|
    opts[:stdout]=v
  } 
  oparser.on("-u","--unlimit","Unlimit all resource limits"){|v|
    opts[:unlimit]=v
  } 
  oparser.on("-v","--version VERSION","Which version to use ( default: #{WhiteSpace::DEFAULTVER} )") {|v|
    opts[:version]=v
  } 
  oparser.on("-d","--debug","Enable debug operations") {|v|
    opts[:debug]=v
  } 
  params = oparser.parse(argv)
   
  raise "No files specified in ARGV" if params.empty?
  raise "Too much ARGV" if params.size>1
   
  WhiteSpace::checkVersion(opts[:version]) 
   
  opts[:ifile]=ifile=params[0] 
   
  if opts[:noexec]
    [:reportexec,:stdin,:stdout,:unlimit].each{|s|
      raise "Wrong option #{opt} for -n/--noexec" if opts[s]
    }
    raise "Nothing to do" if !opts[:disassemble]&&!opts[:assemble]
  end 
   
  filebase=nil 
  if opts[:itype]==:auto
    _,filebase,suffix=/^(.*)\.(\w+)$/.match(ifile).to_a
    opts[:itype]={ "ws"=>:raw, "wsv"=>:stn, "wss"=>:wss }[suffix] or raise "Unknown file type: #{ifile}"
  end 
  raise "Cannot disassemble this type" if opts[:disassemble]&&opts[:itype]==:wss
  raise "Cannot assemble this type" if opts[:assemble]&&opts[:itype]!=:wss
  raise "Debug mode is only allowed for 'wss' file" if opts[:debug]&&opts[:itype]!=:wss
  if opts[:disassemble]
    if !opts[:ofile]
      raise "Decide filename to save disassembled source" if !filebase
      opts[:ofile]=filebase+".wss"
    end
  elsif opts[:assemble]
    if !opts[:ofile]
      raise "Decide filename to save assembled source" if !filebase
      opts[:ofile]=filebase+(opts[:otype]==:raw ? ".ws" : ".wsv")
    end
  else 
    raise "-o/--ofile option without assembling or disassembling" if opts[:ofile]
  end 
   
  opts 
end   
   
def fileOpen(file,mode,usage=nil)  
  File.open(file,mode) or raise "Failed to open #{file}"+(usage ? " for #{usage}" : "")
end   
   
def doCommand(argv)  
  opts=optParse(argv) 
   
  ifile=fileOpen(opts[:ifile],"r") 
  if opts[:itype]==:wss
    as=WhiteSpace::Assembler.new
    code=as.load(ifile,ver:opts[:version])
    if opts[:ofile]
      ofile=fileOpen(opts[:ofile],"w","assembled code")
      case opts[:otype]
      when :raw; ofile.print(code.rcode.join.tr("stn"," \t\n"))
      when :stn; ofile.print(code.rcode.join)
      else     ; raise "Unexpected"
      end
      ofile.close
    end
  else 
    ld=WhiteSpace::Loader.new
    code=ld.load(ifile,ver:opts[:version])
    if opts[:ofile]
      ofile=fileOpen(opts[:ofile],"w","disassembled code")
      code.acode.size.times{|i|
        ofile.puts("%-12s  # %04d: %s" % [code.acode[i],code.info[:pos][i],code.rcode[i]])
      }
      ofile.close
    end
  end 
   
  if !opts[:quiet]
    code.info[:warn].each{|s|
      $stderr.puts s
    }
  end 
   
  if opts[:reportcode]
    $stderr.puts \
      "** Code summary **",
      "  size statistics:",
      "    inst: #{code.info[:size][:inst]}",
      "    byte: #{code.info[:size][:byte]}bytes",
      "  label statistics:"
    code.info[:label].each{|r|
      relabel=r[:relabel] ? ", relabeld to '#{r[:relabel]}'" : ""
      regpos=r[:ip] ? "registered at ip #{r[:ip]}, #{r[:pos]}" : "unregistered"
      $stderr.puts "    #{r[:label]}: used #{r[:count]} times#{relabel}, #{regpos}"
    }
  end 
   
  if !opts[:noexec]
    raise "Quit execution due to code warnings" if opts[:strict]&&!code.info[:warn].empty?
    sin = opts[:stdin] ? fileOpen(opts[:stdin],"r") : $stdin
    sout = opts[:stdout] ? fileOpen(opts[:stdout],"w") : $stdout
    limit = opts[:unlimit] ? { :step=>Float::INIFINITY, :stacksize=>Float::INFINITY, :heapelems=>Float::INFINITY, :calldepth=>Float::INFINITY } : {}
    vm=WhiteSpace::VM.new(code,sin:sin,sout:sout,limit:limit,debug:opts[:debug])
    result=vm.run
    if opts[:reportexec]
      $stderr.puts result.inspect
    end
    exit 1 if result.error
  end 
end   
   
if __FILE__ == $0
  require 'optparse'
  doCommand(ARGV) 
end
  
 
 
			
 
 
	  
	
  
 


   

	 

  	




