import 'script_matcher.dart';

List<List<String>> spokenForms(ScriptWord word) {
  final forms = <List<String>>[[word.normalized]];
  final n = int.tryParse(word.text);
  if (n != null && n >= 0 && n <= 99) forms.add(numberPt(n).split(' '));
  const names = {'A':'a','B':'be','C':'ce','D':'de','E':'e','F':'efe','G':'ge','H':'aga','I':'i','J':'jota','K':'ca','L':'ele','M':'eme','N':'ene','O':'o','P':'pe','Q':'que','R':'erre','S':'esse','T':'te','U':'u','V':'ve','W':'dabliu','X':'xis','Y':'ipsilon','Z':'ze'};
  const acronyms = {'CPF','CNPJ','RG','CEP','INSS','SUS','MEI','NR','EPI','IA','TI','FGTS','PDF','CRM','CLT','ABNT'};
  final m = RegExp(r'^([A-Z]+)([0-9]*)$').firstMatch(word.text);
  if (m != null && acronyms.contains(m.group(1))) {
    final prefix = m.group(1)!;
    final suffix = m.group(2)!;
    final spelled = prefix.split('').map((c) => names[c]!).toList();
    if (suffix.isEmpty) {
      forms.add(spelled);
    } else {
      final value = int.tryParse(suffix);
      forms.add([prefix.toLowerCase(), suffix]);
      forms.add([...spelled, suffix]);
      if (value != null && value <= 99) {
        forms.add([prefix.toLowerCase(), ...numberPt(value).split(' ')]);
        forms.add([...spelled, ...numberPt(value).split(' ')]);
      }
    }
  }
  return forms;
}

String numberPt(int n) {
  const units = {0:'zero',1:'um',2:'dois',3:'tres',4:'quatro',5:'cinco',6:'seis',7:'sete',8:'oito',9:'nove',10:'dez',11:'onze',12:'doze',13:'treze',14:'quatorze',15:'quinze',16:'dezesseis',17:'dezessete',18:'dezoito',19:'dezenove'};
  const tens = {2:'vinte',3:'trinta',4:'quarenta',5:'cinquenta',6:'sessenta',7:'setenta',8:'oitenta',9:'noventa'};
  if (n < 20) return units[n]!;
  final tail = n % 10;
  return tail == 0 ? tens[n ~/ 10]! : [tens[n ~/ 10]!, 'e', units[tail]!].join(' ');
}
