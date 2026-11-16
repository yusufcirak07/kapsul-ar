import 'package:flutter/material.dart';

class PixelArtViewer extends StatelessWidget {
  final List<int> grid;
  final double size;

  const PixelArtViewer({
    super.key,
    required this.grid,
    this.size = 160,
  });

  @override
  Widget build(BuildContext context) {
    final cells = grid.length >= 256
        ? grid.take(256).toList()
        : [...grid, ...List.filled(256 - grid.length, 0)];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(6),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 16,
        ),
        itemCount: 256,
        itemBuilder: (_, idx) {
          final argb = cells[idx];
          return Container(
            color: argb == 0 ? Colors.transparent : Color(argb),
          );
        },
      ),
    );
  }
}

class PixelArtEditor extends StatefulWidget {
  final List<int> initialGrid;
  final ValueChanged<List<int>> onChanged;

  const PixelArtEditor({
    super.key,
    required this.initialGrid,
    required this.onChanged,
  });

  @override
  State<PixelArtEditor> createState() => _PixelArtEditorState();
}

class _PixelArtEditorState extends State<PixelArtEditor> {
  static const List<Color> _palette = [
    Color(0xFF1E3A8A), // İndigo
    Color(0xFF0D9488), // Turkuaz
    Color(0xFFF59E0B), // Kehribar
    Color(0xFFEF4444), // Mercan
    Color(0xFF10B981), // Zümrüt
    Color(0xFF8B5CF6), // Menekşe
    Color(0xFF0F172A), // Koyu Lacivert
    Color(0x00000000), // Silgi
  ];

  late List<int> _cells;
  Color _selectedColor = _palette[0];

  @override
  void initState() {
    super.initState();
    _cells = widget.initialGrid.length == 256
        ? List<int>.from(widget.initialGrid)
        : List<int>.filled(256, 0);
  }

  void _paintCell(int index) {
    setState(() {
      _cells[index] = _selectedColor.toARGB32();
    });
    widget.onChanged(List<int>.from(_cells));
  }

  void _clear() {
    setState(() {
      _cells = List<int>.filled(256, 0);
    });
    widget.onChanged(List<int>.from(_cells));
  }

  void _loadHeartPreset() {
    const heart =
        '0000000000000000'
        '0001110000111000'
        '0011111001111100'
        '0111111111111110'
        '0111111111111110'
        '0111111111111110'
        '0011111111111100'
        '0001111111111000'
        '0000111111110000'
        '0000011111100000'
        '0000001111000000'
        '0000000110000000'
        '0000000000000000'
        '0000000000000000'
        '0000000000000000'
        '0000000000000000';
    final color = const Color(0xFFEF4444).toARGB32();
    setState(() {
      _cells = heart.split('').map((c) => c == '1' ? color : 0).toList();
    });
    widget.onChanged(List<int>.from(_cells));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '16×16 Piksel Sanat Tuvali',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _loadHeartPreset,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Örnek'),
            ),
            TextButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Temizle'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 256,
            height: 256,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 16,
              ),
              itemCount: 256,
              itemBuilder: (_, idx) {
                final argb = _cells[idx];
                return GestureDetector(
                  onTap: () => _paintCell(idx),
                  child: Container(
                    decoration: BoxDecoration(
                      color: argb == 0 ? const Color(0xFFF8FAFC) : Color(argb),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                        width: 0.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          children: _palette.map((c) {
            final isSelected = _selectedColor.toARGB32() == c.toARGB32();
            final isEraser = c.a == 0;
            return GestureDetector(
              onTap: () => setState(() => _selectedColor = c),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isEraser ? Colors.white : c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFCBD5E1),
                    width: isSelected ? 2.5 : 1,
                  ),
                ),
                child: isEraser
                    ? const Icon(Icons.cleaning_services_outlined, size: 16)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
