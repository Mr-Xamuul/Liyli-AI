import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:leyli/widgets/rich_tutor_markdown.dart';

void main() {
  testWidgets('RichTutorMarkdown renders headings, blockquotes, inline math, and display math properly', (tester) async {
    const rawText = '''
* **Xiriirka tooska ah ee ka dhexeeya \$T\$ iyo \$f\$:**
  Labadaan cabbir waa isku rogane:
  \$\$f = \\frac{1}{T} \\quad \\text{iyo} \\quad T = \\frac{1}{f}\$\$

---

### 🔢 3. Xallinta Tusaalooyinka Buugga (Examples)

#### **Tusaale 1.1:**
> *Cuf laalaada ayaa sameeyay 60 wareeg.*

* **Xogta la bixiyay:**
  * Tirada wareegyada = \$60\$
  * Waqtiga = \$15\\text{ s}\$
''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RichTutorMarkdown(text: rawText),
          ),
        ),
      ),
    );

    // Should find multiple rendered Math widgets (inline formulas $T$, $f$, $60$, $15\text{ s}$ and block formula)
    expect(find.byType(Math), findsAtLeastNWidgets(3));
    expect(find.textContaining('Xallinta Tusaalooyinka Buugga'), findsOneWidget);
    expect(find.textContaining('Cuf laalaada ayaa sameeyay'), findsOneWidget);
  });
}
