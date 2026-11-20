import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const LedgerApp()); }
const emerald = Color(0xff21c66a);
const scarlet = Color(0xffef5555);
const categories = ['NIFTY/BANKNIFTY/SENSEX','STOCK OPTION','EQUITY','COMMODITY'];
final currency = NumberFormat.currency(locale:'en_IN',symbol:'₹',decimalDigits:2);
String rs(int p) => currency.format(p/100);
String dateText(DateTime d) => DateFormat('dd MMM yyyy').format(d);
String monthText(DateTime d) => DateFormat('MMMM yyyy').format(d);
int? parsePaise(String value) { final v=double.tryParse(value.trim()); if(v==null || !v.isFinite || v<=0 || v>100000000000) return null; return (v*100).round(); }

class Trade {
  final String id, note, category, friend;
  final DateTime date;
  final int paise;
  const Trade({required this.id,required this.note,required this.category,required this.friend,required this.date,required this.paise});
  factory Trade.fromJson(Map<String,dynamic> j) => Trade(
    id: '${j['id'] ?? ''}', note:'${j['note'] ?? ''}', category:'${j['category'] ?? 'Uncategorized'}',
    friend:'${j['friend'] ?? ''}', date:DateTime.tryParse('${j['date']}') ?? DateTime.now(),
    paise: (j['amountPaise'] as num?)?.toInt() ?? (j['paise'] as num?)?.toInt() ?? 0,
  );
  Map<String,dynamic> toJson()=>{'id':id,'note':note,'category':category,'friend':friend,'date':date.toIso8601String(),'amountPaise':paise};
}

class LedgerApp extends StatefulWidget { const LedgerApp({super.key}); @override State<LedgerApp> createState()=>_LedgerAppState(); }
class _LedgerAppState extends State<LedgerApp> {
  ThemeMode mode=ThemeMode.dark;
  @override void initState(){super.initState(); _loadTheme();}
  Future<void> _loadTheme() async { final p=await SharedPreferences.getInstance(); if(mounted) setState(()=>mode=p.getBool('tlp_dark_v2')==false?ThemeMode.light:ThemeMode.dark); }
  Future<void> toggleTheme() async { final next=mode==ThemeMode.dark?ThemeMode.light:ThemeMode.dark; setState(()=>mode=next); final p=await SharedPreferences.getInstance(); await p.setBool('tlp_dark_v2',next==ThemeMode.dark); }
  @override Widget build(BuildContext context)=>MaterialApp(
    debugShowCheckedModeBanner:false,title:'Trade Ledger Pro',themeMode:mode,
    theme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:emerald,brightness:Brightness.light),scaffoldBackgroundColor:const Color(0xfff5f7f8)),
    darkTheme:ThemeData(useMaterial3:true,colorScheme:ColorScheme.fromSeed(seedColor:emerald,brightness:Brightness.dark),scaffoldBackgroundColor:const Color(0xff0b121b),cardTheme:const CardThemeData(color:Color(0xff172331))),
    home:LedgerHome(dark:mode==ThemeMode.dark,onTheme:toggleTheme),
  );
}

class LedgerHome extends StatefulWidget {
  final bool dark; final VoidCallback onTheme;
  const LedgerHome({super.key,required this.dark,required this.onTheme});
  @override State<LedgerHome> createState()=>_LedgerHomeState();
}
class _LedgerHomeState extends State<LedgerHome> {
  static const personalKey='pnl_entries_v1'; // PRESERVE v1 data and existing app package identity.
  static const friendKey='tlp_friend_entries_v2';
  static const namesKey='tlp_friends_v2';
  List<Trade> personal=[], joint=[];
  List<String> friends=[];
  bool loading=true;
  int tab=0;
  DateTime selectedMonth=DateTime(DateTime.now().year,DateTime.now().month);
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    try {
      final p=await SharedPreferences.getInstance();
      List<Trade> decode(String key){final raw=p.getString(key);if(raw==null)return [];return (jsonDecode(raw) as List).map((e)=>Trade.fromJson(Map<String,dynamic>.from(e as Map))).toList();}
      final a=decode(personalKey),b=decode(friendKey),n=p.getStringList(namesKey)??[];
      if(mounted)setState((){personal=a;joint=b;friends=n;loading=false;});
    } catch(e){if(mounted){setState(()=>loading=false);alert('Saved data could not be loaded. Nothing was overwritten.');}}
  }
  Future<bool> save({List<Trade>? personalNext,List<Trade>? jointNext,List<String>? friendsNext}) async {
    try {
      final p=await SharedPreferences.getInstance();
      if(personalNext!=null && !await p.setString(personalKey,jsonEncode(personalNext.map((e)=>e.toJson()).toList())))throw Exception('Save failed');
      if(jointNext!=null && !await p.setString(friendKey,jsonEncode(jointNext.map((e)=>e.toJson()).toList())))throw Exception('Save failed');
      if(friendsNext!=null && !await p.setStringList(namesKey,friendsNext))throw Exception('Save failed');
      if(mounted)setState((){if(personalNext!=null)personal=personalNext;if(jointNext!=null)joint=jointNext;if(friendsNext!=null)friends=friendsNext;});
      return true;
    }catch(e){alert('Could not save: $e');return false;}
  }
  void alert(String message){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}
  Future<bool> confirm(String title,String body) async => await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:Text(title),content:Text(body),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Confirm'))]))??false;
  Future<void> editTrade({Trade? trade,bool isFriend=false}) async {
    if(isFriend && friends.isEmpty){await addFriend();if(friends.isEmpty)return;}
    final updated=await showModalBottomSheet<Trade>(context:context,isScrollControlled:true,showDragHandle:true,builder:(c)=>TradeEditor(existing:trade,friendMode:isFriend,friendNames:friends));
    if(updated==null)return;
    final old=isFriend?joint:personal;
    final next=[...old];final index=next.indexWhere((e)=>e.id==updated.id);
    if(index<0){next.add(updated);}else{next[index]=updated;}
    await save(personalNext:isFriend?null:next,jointNext:isFriend?next:null);
  }
  Future<void> deleteTrade(Trade t,bool friendMode) async {
    if(!await confirm('Delete entry?','This trade will be permanently deleted.'))return;
    final next=(friendMode?joint:personal).where((e)=>e.id!=t.id).toList();
    await save(personalNext:friendMode?null:next,jointNext:friendMode?next:null);
  }
  Future<void> addFriend() async {
    final controller=TextEditingController();
    final name=await showDialog<String>(context:context,builder:(c)=>AlertDialog(title:const Text('Add friend'),content:TextField(controller:controller,textCapitalization:TextCapitalization.words,autofocus:true,maxLength:40,decoration:const InputDecoration(labelText:'Friend name')),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,controller.text.trim()),child:const Text('Add'))]));
    controller.dispose();if(name==null||name.isEmpty)return;
    if(friends.any((e)=>e.toLowerCase()==name.toLowerCase())){alert('Friend already exists');return;}
    await save(friendsNext:[...friends,name]);
  }
  Future<void> reset() async {
    if(!await confirm('Reset all data?','This deletes all personal trades, friend trades and friend names.'))return;
    if(!mounted)return;
    if(!await confirm('Final confirmation','This cannot be undone. Delete ALL trading records?'))return;
    await save(personalNext:[],jointNext:[],friendsNext:[]);
  }
  int sum(Iterable<Trade> list)=>list.fold(0,(v,e)=>v+e.paise);
  int profit(Iterable<Trade> list)=>list.where((e)=>e.paise>0).fold(0,(v,e)=>v+e.paise);
  int loss(Iterable<Trade> list)=>list.where((e)=>e.paise<0).fold(0,(v,e)=>v-e.paise);
  Widget panel(Widget child)=>Card(margin:const EdgeInsets.symmetric(vertical:7),child:Padding(padding:const EdgeInsets.all(16),child:child));
  Widget labelValue(String title,String value,Color color)=>Expanded(child:panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:12)),const SizedBox(height:8),Text(value,style:TextStyle(color:color,fontSize:18,fontWeight:FontWeight.bold))])));
  @override Widget build(BuildContext context){
    final net=sum(personal);final isLoss=net<0;
    return Scaffold(
      appBar:AppBar(toolbarHeight:86,title:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('जय श्री पूनरासर',style:TextStyle(fontSize:14,color:Color(0xffe6b34b),fontWeight:FontWeight.bold)),const Text('Trade Ledger Pro',style:TextStyle(fontWeight:FontWeight.bold,fontSize:21))]),actions:[IconButton(tooltip:'Toggle theme',onPressed:widget.onTheme,icon:Icon(widget.dark?Icons.light_mode_outlined:Icons.dark_mode_outlined)),PopupMenuButton<String>(onSelected:(s){if(s=='reset')reset();},itemBuilder:(c)=>[const PopupMenuItem(value:'reset',child:Text('Reset all data'))])]),
      body:loading?const Center(child:CircularProgressIndicator()):IndexedStack(index:tab,children:[dashboard(),tradesPage(),reportsPage(),calculatorPage(),friendsPage()]),
      floatingActionButton:tab==0||tab==1||tab==4?FloatingActionButton.extended(onPressed:()=>editTrade(isFriend:tab==4),icon:const Icon(Icons.add),label:Text(tab==4?'Friend trade':'Add trade')):null,
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [NavigationDestination(icon:Icon(Icons.dashboard_outlined),label:'Home'),NavigationDestination(icon:Icon(Icons.receipt_long_outlined),label:'Trades'),NavigationDestination(icon:Icon(Icons.picture_as_pdf_outlined),label:'Reports'),NavigationDestination(icon:Icon(Icons.calculate_outlined),label:'Average'),NavigationDestination(icon:Icon(Icons.people_outline),label:'Friends')]),
    );
  }
  Widget dashboard(){
    final net=sum(personal);final negative=net<0;
    final current=personal.where((e)=>e.date.year==DateTime.now().year&&e.date.month==DateTime.now().month).toList();
    final ordered=[...personal]..sort((a,b)=>b.date.compareTo(a.date));
    return ListView(padding:const EdgeInsets.all(12),children:[
      panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('ALL-TIME P&L',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:10),Text(negative?'Loss to Recover':'Net Profit',style:TextStyle(color:negative?scarlet:emerald)),Text(rs(negative?-net:net),style:TextStyle(fontSize:32,fontWeight:FontWeight.bold,color:negative?scarlet:emerald)),if(!negative)const Text('✓ All Loss Recovered!',style:TextStyle(color:emerald))])),
      Row(children:[labelValue('Total Profit',rs(profit(personal)),emerald),labelValue('Total Loss',rs(loss(personal)),scarlet)]),
      panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('CATEGORY-WISE P&L (ALL TIME)',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:12),GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.05,children:categories.map((cat){final n=sum(personal.where((e)=>e.category==cat));final maxTotal=math.max(profit(personal)+loss(personal),1);return Column(children:[SizedBox(width:112,height:112,child:Stack(alignment:Alignment.center,children:[SizedBox.expand(child:CircularProgressIndicator(value:math.min(n.abs()/maxTotal,1),strokeWidth:9,backgroundColor:Theme.of(context).dividerColor,valueColor:AlwaysStoppedAnimation(n<0?scarlet:emerald))),Padding(padding:const EdgeInsets.all(12),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text(cat,style:const TextStyle(fontSize:9,fontWeight:FontWeight.bold),textAlign:TextAlign.center,maxLines:3),FittedBox(child:Text('${n<0?'-':'+'}${rs(n.abs())}',style:TextStyle(color:n<0?scarlet:emerald,fontWeight:FontWeight.bold)))]))]))]);}).toList())])),
      panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('THIS MONTH (${monthText(DateTime.now())})',style:const TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:12),summaryLine('Profit',rs(profit(current)),emerald),summaryLine('Loss',rs(loss(current)),scarlet),summaryLine('Net P&L',rs(sum(current)),sum(current)<0?scarlet:emerald)])),
      Wrap(spacing:8,runSpacing:8,children:[ActionChip(avatar:const Icon(Icons.picture_as_pdf),label:const Text('PDF Reports'),onPressed:()=>setState(()=>tab=2)),ActionChip(avatar:const Icon(Icons.people),label:const Text('Friend Trading'),onPressed:()=>setState(()=>tab=4)),ActionChip(avatar:const Icon(Icons.calculate),label:const Text('Average Calculator'),onPressed:()=>setState(()=>tab=3))]),
      const SizedBox(height:12),const Text('Recent Entries',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),...ordered.take(6).map((e)=>tradeTile(e,false)),if(ordered.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('No entries yet. Tap Add trade to begin.')),
    ]);
  }
  Widget summaryLine(String name,String value,Color c)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(name),Text(value,style:TextStyle(color:c,fontWeight:FontWeight.bold))]));
  Widget tradeTile(Trade t,bool isFriend)=>Card(child:ListTile(onTap:()=>editTrade(trade:t,isFriend:isFriend),title:Text(t.category=='Uncategorized'?(t.note.isEmpty?'Uncategorized':t.note):t.category,maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text('${dateText(t.date)}${t.note.isEmpty?'':' • ${t.note}'}${isFriend?' • ${t.friend}':''}'),trailing:Row(mainAxisSize:MainAxisSize.min,children:[Text('${t.paise>=0?'+':'−'}${rs(t.paise.abs())}',style:TextStyle(color:t.paise>=0?emerald:scarlet,fontWeight:FontWeight.bold)),PopupMenuButton<String>(onSelected:(s){if(s=='edit')editTrade(trade:t,isFriend:isFriend);if(s=='delete')deleteTrade(t,isFriend);},itemBuilder:(c)=>const [PopupMenuItem(value:'edit',child:Text('Edit')),PopupMenuItem(value:'delete',child:Text('Delete'))])])));
  Widget tradesPage(){final ordered=[...personal]..sort((a,b)=>b.date.compareTo(a.date));return ListView(padding:const EdgeInsets.all(12),children:[const Text('Personal Trades',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const Text('Tap any entry to edit it.'),...ordered.map((e)=>tradeTile(e,false)),if(ordered.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No personal trades yet.'))]);}
  Widget reportsPage(){final months=personal.map((e)=>DateTime(e.date.year,e.date.month)).toSet().toList()..sort((a,b)=>b.compareTo(a));if(!months.contains(selectedMonth))months.add(selectedMonth);months.sort((a,b)=>b.compareTo(a));final monthEntries=personal.where((e)=>e.date.year==selectedMonth.year&&e.date.month==selectedMonth.month).toList();return ListView(padding:const EdgeInsets.all(12),children:[const Text('Reports & PDF Export',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:12),DropdownButtonFormField<DateTime>(initialValue:selectedMonth,decoration:const InputDecoration(labelText:'Select month',border:OutlineInputBorder()),items:months.map((m)=>DropdownMenuItem(value:m,child:Text(monthText(m)))).toList(),onChanged:(m){if(m!=null)setState(()=>selectedMonth=m);}),const SizedBox(height:10),panel(Column(children:[summaryLine('Monthly Profit',rs(profit(monthEntries)),emerald),summaryLine('Monthly Loss',rs(loss(monthEntries)),scarlet),summaryLine('Monthly Net',rs(sum(monthEntries)),sum(monthEntries)<0?scarlet:emerald),const Divider(),...categories.map((c)=>summaryLine(c,rs(sum(monthEntries.where((e)=>e.category==c))),sum(monthEntries.where((e)=>e.category==c))<0?scarlet:emerald))])),FilledButton.icon(onPressed:()=>exportPdf('Monthly - ${monthText(selectedMonth)}',monthEntries),icon:const Icon(Icons.download),label:const Text('Download / Share Monthly PDF')),const SizedBox(height:8),OutlinedButton.icon(onPressed:()=>exportPdf('All-Time Personal',personal),icon:const Icon(Icons.picture_as_pdf),label:const Text('All-Time Personal PDF')),const SizedBox(height:8),OutlinedButton.icon(onPressed:()=>exportPdf('Friend Trading 50-50',joint,friendMode:true),icon:const Icon(Icons.people),label:const Text('Friend Trading PDF')),const SizedBox(height:12),const Text('PDF files are created offline. Use the Android share/save dialog to store them.')]);}
  Future<void> exportPdf(String title,List<Trade> list,{bool friendMode=false}) async {
    try {
      final doc=pw.Document();final ordered=[...list]..sort((a,b)=>b.date.compareTo(a.date));
      final positive=profit(ordered),negative=loss(ordered),net=sum(ordered);
      doc.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4,build:(c)=>[
        pw.Text('TRADE LEDGER PRO',style:pw.TextStyle(fontSize:20,fontWeight:pw.FontWeight.bold)),pw.Text(title),pw.SizedBox(height:12),
        pw.Text('Total Profit: INR ${(positive/100).toStringAsFixed(2)}   Total Loss: INR ${(negative/100).toStringAsFixed(2)}'),
        pw.Text('Net P&L: INR ${(net/100).toStringAsFixed(2)}'),
        if(friendMode)pw.Text('Each partner share (50%): INR ${(net/200).toStringAsFixed(2)}'),
        pw.SizedBox(height:16),pw.TableHelper.fromTextArray(headers:friendMode?['Date','Friend','Category','Trade P&L','Each 50%']:['Date','Category','Note','P&L'],data:ordered.map((e)=>friendMode?[dateText(e.date),e.friend,e.category,(e.paise/100).toStringAsFixed(2),(e.paise/200).toStringAsFixed(2)]:[dateText(e.date),e.category,e.note,(e.paise/100).toStringAsFixed(2)]).toList()),
      ]));
      await Printing.sharePdf(bytes:await doc.save(),filename:'trade_ledger_${DateTime.now().millisecondsSinceEpoch}.pdf');
    }catch(e){alert('PDF export failed: $e');}
  }
  Widget friendsPage(){final net=sum(joint);return ListView(padding:const EdgeInsets.all(12),children:[const Text('Friend Trading (50-50)',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const Text('Completely separate from Personal P&L.'),panel(Column(children:[summaryLine('Combined Net P&L',rs(net),net<0?scarlet:emerald),summaryLine('Your 50% Share',rs((net/2).round()),net<0?scarlet:emerald),summaryLine('Friend 50% Share',rs(net-(net/2).round()),net<0?scarlet:emerald)])),OutlinedButton.icon(onPressed:addFriend,icon:const Icon(Icons.person_add),label:const Text('Add Friend')),const SizedBox(height:12),...friends.map((name){final trades=joint.where((e)=>e.friend==name).toList();final n=sum(trades);return panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(name,style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),summaryLine('Total P&L',rs(n),n<0?scarlet:emerald),summaryLine('Your share',rs((n/2).round()),n<0?scarlet:emerald),summaryLine('Friend share',rs(n-(n/2).round()),n<0?scarlet:emerald)]));}),const SizedBox(height:12),const Text('Friend Trade Entries',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),...([...joint]..sort((a,b)=>b.date.compareTo(a.date))).map((e)=>tradeTile(e,true))]);}
  Widget calculatorPage()=>const AverageCalculator();
}

class TradeEditor extends StatefulWidget {
  final Trade? existing; final bool friendMode; final List<String> friendNames;
  const TradeEditor({super.key,this.existing,required this.friendMode,required this.friendNames});
  @override State<TradeEditor> createState()=>_TradeEditorState();
}
class _TradeEditorState extends State<TradeEditor> {
  late final TextEditingController amount,note;
  late bool isProfit;
  late DateTime date;
  String? category,friend;
  @override void initState(){super.initState();final e=widget.existing;amount=TextEditingController(text:e==null?'':(e.paise.abs()/100).toStringAsFixed(2));note=TextEditingController(text:e?.note??'');isProfit=(e?.paise??1)>=0;date=e?.date??DateTime.now();category=categories.contains(e?.category)?e!.category:null;friend=e?.friend.isNotEmpty==true?e!.friend:(widget.friendNames.isNotEmpty?widget.friendNames.first:null);}
  @override void dispose(){amount.dispose();note.dispose();super.dispose();}
  void submit(){final value=parsePaise(amount.text);if(value==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid amount greater than zero.')));return;}if(category==null){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Select a trading category.')));return;}if(widget.friendMode&&friend==null)return;Navigator.pop(context,Trade(id:widget.existing?.id??DateTime.now().microsecondsSinceEpoch.toString(),note:note.text.trim(),category:category!,friend:widget.friendMode?friend!:'',date:date,paise:isProfit?value:-value));}
  @override Widget build(BuildContext context)=>Padding(padding:EdgeInsets.only(left:20,right:20,bottom:MediaQuery.viewInsetsOf(context).bottom+24),child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(widget.existing==null?'Add Trade':'Edit Trade',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:16),SegmentedButton<bool>(segments:const [ButtonSegment(value:true,label:Text('Profit'),icon:Icon(Icons.trending_up)),ButtonSegment(value:false,label:Text('Loss'),icon:Icon(Icons.trending_down))],selected:{isProfit},onSelectionChanged:(s)=>setState(()=>isProfit=s.first)),const SizedBox(height:14),TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),inputFormatters:[FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],decoration:const InputDecoration(labelText:'Amount (₹)',border:OutlineInputBorder())),const SizedBox(height:14),DropdownButtonFormField<String>(initialValue:category,decoration:const InputDecoration(labelText:'Trading Category *',border:OutlineInputBorder()),items:categories.map((e)=>DropdownMenuItem(value:e,child:Text(e,style:const TextStyle(fontSize:13)))).toList(),onChanged:(v)=>setState(()=>category=v)),if(widget.friendMode)...[const SizedBox(height:14),DropdownButtonFormField<String>(initialValue:friend,decoration:const InputDecoration(labelText:'Friend *',border:OutlineInputBorder()),items:widget.friendNames.map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setState(()=>friend=v))],const SizedBox(height:14),OutlinedButton.icon(onPressed:() async {final picked=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2100));if(picked!=null)setState(()=>date=picked);},icon:const Icon(Icons.calendar_today),label:Text(dateText(date))),const SizedBox(height:14),TextField(controller:note,maxLength:100,decoration:const InputDecoration(labelText:'Note (optional)',border:OutlineInputBorder())),const SizedBox(height:8),FilledButton(onPressed:submit,child:const Text('Save Trade'))])));
}

class AverageCalculator extends StatefulWidget {const AverageCalculator({super.key});@override State<AverageCalculator> createState()=>_AverageCalculatorState();}
class _AverageCalculatorState extends State<AverageCalculator> {
  final controllers=List.generate(4,(_)=>TextEditingController());
  @override void dispose(){for(final c in controllers){c.dispose();}super.dispose();}
  Widget field(int i,String label)=>TextField(controller:controllers[i],keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(_)=>setState((){}),decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()));
  @override Widget build(BuildContext context){final v=controllers.map((e)=>double.tryParse(e.text)??0).toList();final valid=v.every((e)=>e.isFinite&&e>=0)&&v[0]+v[2]>0;final qty=v[0]+v[2];final investment=v[0]*v[1]+v[2]*v[3];return ListView(padding:const EdgeInsets.all(16),children:[const Text('Stock Average Calculator',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:14),field(0,'Existing Quantity'),const SizedBox(height:12),field(1,'Existing Buy Price ₹'),const SizedBox(height:12),field(2,'New Buy Quantity'),const SizedBox(height:12),field(3,'New Buy Price ₹'),const SizedBox(height:20),Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('New Average Price'),Text(valid?currency.format(investment/qty):'—',style:const TextStyle(fontSize:30,color:emerald,fontWeight:FontWeight.bold)),const SizedBox(height:8),Text('Total Quantity: ${valid?qty.toStringAsFixed(2):'—'}'),Text('Total Investment: ${valid?currency.format(investment):'—'}')]))),const Text('Average excludes brokerage, taxes and other charges.')]);}
}

