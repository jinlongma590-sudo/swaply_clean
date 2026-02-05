// lib/pages/edit_profile_page.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:swaply/services/profile_service.dart';
import 'package:swaply/services/image_normalizer.dart';
import 'package:swaply/router/root_nav.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  EditProfilePageState createState() => EditProfilePageState();
}

class EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();

  String _selectedCity = 'Harare';
  String? _avatarUrl;
  Uint8List? _selectedImageBytes; // bytes 存储头像
  bool _loading = true;
  bool _saving = false;

  final List<String> _cities = const [
    'Harare',
    'Bulawayo',
    'Chitungwiza',
    'Mutare',
    'Gweru',
    'Kwekwe',
    'Kadoma',
    'Masvingo',
    'Chinhoyi',
    'Chegutu',
    'Bindura',
    'Marondera',
    'Redcliff'
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileService.instance.getUserProfile();
      final user = Supabase.instance.client.auth.currentUser;

      if (mounted && profile != null) {
        setState(() {
          _nameController.text = profile['display_name'] ??
              profile['full_name'] ??
              user?.userMetadata?['full_name'] ??
              user?.email?.split('@').first ??
              '';
          _phoneController.text = profile['phone'] ?? user?.phone ?? '';
          _bioController.text = profile['bio'] ?? '';
          _selectedCity = profile['city'] ?? 'Harare';
          _avatarUrl = profile['avatar_url'];
          _loading = false;
        });
      } else if (mounted) {
        setState(() {
          _nameController.text = user?.userMetadata?['full_name'] ??
              user?.email?.split('@').first ??
              '';
          _phoneController.text = user?.phone ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e',
                style: TextStyle(fontSize: 14.sp)),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24.r),
              topRight: Radius.circular(24.r),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40.w,
                  height: 4.h,
                  margin: EdgeInsets.only(top: 12.h, bottom: 16.h),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
                _buildImagePickerOption(
                  icon: Icons.camera_alt_rounded,
                  title: 'Take Photo',
                  onTap: () async {
                    navMaybePop();
                    final image = await picker.pickImage(
                      source: ImageSource.camera,
                      imageQuality: 70,
                      maxWidth: 500,
                      maxHeight: 500,
                    );
                    if (image != null) {
                      // 统一 JPG + 规范化
                      final norm = await ImageNormalizer.normalizeXFile(image);
                      setState(() {
                        _selectedImageBytes = norm.bytes;
                      });
                    }
                  },
                ),
                _buildImagePickerOption(
                  icon: Icons.photo_library_rounded,
                  title: 'Choose from Gallery',
                  onTap: () async {
                    navMaybePop();
                    final image = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 70,
                      maxWidth: 500,
                      maxHeight: 500,
                    );
                    if (image != null) {
                      final norm = await ImageNormalizer.normalizeXFile(image);
                      setState(() {
                        _selectedImageBytes = norm.bytes;
                      });
                    }
                  },
                ),
                if (_avatarUrl != null || _selectedImageBytes != null)
                  _buildImagePickerOption(
                    icon: Icons.delete_rounded,
                    title: 'Remove Photo',
                    isDestructive: true,
                    onTap: () {
                      navMaybePop();
                      setState(() {
                        _selectedImageBytes = null;
                        _avatarUrl = null;
                      });
                    },
                  ),
                _buildImagePickerOption(
                  icon: Icons.close_rounded,
                  title: 'Cancel',
                  onTap: () => navMaybePop(),
                ),
                SizedBox(height: 16.h),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildImagePickerOption({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color:
                    isDestructive ? Colors.red.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(
                icon,
                color: isDestructive ? Colors.red : Colors.grey.shade700,
                size: 24.w,
              ),
            ),
            SizedBox(width: 16.w),
            Text(
              title,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w500,
                color: isDestructive ? Colors.red : Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      if (user == null) {
        throw 'Not signed in';
      }

      String? newAvatarUrl = _avatarUrl;

      // 选择了新头像 → 以 bytes 上传（JPG + upsert）
      if (_selectedImageBytes != null) {
        final path =
            'avatars/${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await supa.storage.from('avatars').uploadBinary(
              path,
              _selectedImageBytes!,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: true,
              ),
            );
        newAvatarUrl = supa.storage.from('avatars').getPublicUrl(path);
      }

      // 写 profiles 并刷新 updated_at
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final bio = _bioController.text.trim();
      final city = _selectedCity;

      await supa.from('profiles').update({
        'full_name': name,
        'phone': phone.isEmpty ? null : phone,
        'avatar_url': newAvatarUrl,
        'bio': bio,
        'city': city,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', user.id);

      // 清前端缓存；由 pop(true) 通知上层刷新
      ProfileService.instance.invalidateCache(user.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile updated successfully',
              style: TextStyle(fontSize: 14.sp)),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          margin: EdgeInsets.all(16.w),
        ),
      );

      // 返回并告知“有更新”，上层按 result==true 触发刷新
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e',
                style: TextStyle(fontSize: 14.sp)),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildAvatarSection() {
    final hasBytes = _selectedImageBytes != null;
    final hasUrl = _avatarUrl != null && _avatarUrl!.isNotEmpty;

    return Center(
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.3),
                  blurRadius: 20.r,
                  offset: Offset(0, 8.h),
                ),
              ],
            ),
            padding: EdgeInsets.all(4.w),
            child: CircleAvatar(
              radius: 60.r,
              backgroundColor: Colors.white,
              backgroundImage: hasBytes
                  ? MemoryImage(_selectedImageBytes!) as ImageProvider
                  : hasUrl
                      ? NetworkImage(_avatarUrl!) as ImageProvider
                      : null,
              child: (!hasBytes && !hasUrl)
                  ? Icon(Icons.person_rounded,
                      size: 60.w, color: Colors.grey.shade400)
                  : null,
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3.w),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667EEA).withOpacity(0.3),
                      blurRadius: 8.r,
                      offset: Offset(0, 2.h),
                    ),
                  ],
                ),
                child: Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 20.w),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label + (isRequired ? ' *' : ''),
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        SizedBox(height: 8.h),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          maxLength: maxLength,
          validator: validator,
          style: TextStyle(fontSize: 16.sp),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Padding(
              padding: EdgeInsets.all(16.w),
              child: Icon(icon, color: const Color(0xFF667EEA), size: 20.w),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.r),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.r),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.r),
              borderSide:
                  BorderSide(color: const Color(0xFF667EEA), width: 2.w),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.r),
              borderSide: BorderSide(color: Colors.red.shade400, width: 2.w),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            counterText: maxLength != null ? null : '',
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'City',
          style: TextStyle(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        SizedBox(height: 8.h),
        DropdownButtonFormField<String>(
          initialValue: _selectedCity,
          style: TextStyle(fontSize: 16.sp, color: Colors.grey.shade800),
          decoration: InputDecoration(
            prefixIcon: Padding(
              padding: EdgeInsets.all(16.w),
              child: Icon(Icons.location_city_rounded,
                  color: const Color(0xFF667EEA), size: 20.w),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.r),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.r),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16.r),
              borderSide:
                  BorderSide(color: const Color(0xFF667EEA), width: 2.w),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
          ),
          items: _cities
              .map((city) => DropdownMenuItem(value: city, child: Text(city)))
              .toList(),
          onChanged: (value) => setState(() => _selectedCity = value!),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'Edit Profile',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 20.sp),
        ),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24.w),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_loading)
            Container(
              margin: EdgeInsets.only(right: 16.w),
              child: TextButton(
                onPressed: _saving ? null : _saveProfile,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                ),
                child: _saving
                    ? SizedBox(
                        width: 20.w,
                        height: 20.h,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.w, color: Colors.white),
                      )
                    : Text(
                        'Save',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16.sp,
                        ),
                      ),
              ),
            ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF667EEA)),
                strokeWidth: 3.w,
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.all(24.w),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 20.h),
                    _buildAvatarSection(),
                    SizedBox(height: 40.h),
                    _buildTextField(
                      controller: _nameController,
                      label: 'Display Name',
                      hint: 'Enter your display name',
                      icon: Icons.person_outline_rounded,
                      isRequired: true,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your display name';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 24.h),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'Phone Number',
                      hint: '+263 77 123 4567',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    SizedBox(height: 24.h),
                    _buildDropdownField(),
                    SizedBox(height: 24.h),
                    _buildTextField(
                      controller: _bioController,
                      label: 'Bio',
                      hint: 'Tell others about yourself...',
                      icon: Icons.description_outlined,
                      maxLines: 4,
                      maxLength: 500,
                    ),
                    SizedBox(height: 40.h),
                    SizedBox(
                      width: double.infinity,
                      height: 56.h,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16.r)),
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                            ),
                            borderRadius: BorderRadius.circular(16.r),
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            child: _saving
                                ? SizedBox(
                                    width: 24.w,
                                    height: 24.h,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2.w),
                                  )
                                : Text(
                                    'Save Changes',
                                    style: TextStyle(
                                      fontSize: 18.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 24.h),
                    Container(
                      padding: EdgeInsets.all(20.w),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20.r),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20.r,
                            offset: Offset(0, 4.h),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(10.w),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Icon(Icons.info_outline_rounded,
                                    color: Colors.grey.shade600, size: 20.w),
                              ),
                              SizedBox(width: 12.w),
                              Text(
                                'Account Information',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18.sp,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16.h),
                          _buildInfoRow(
                            Icons.email_outlined,
                            Supabase.instance.client.auth.currentUser?.email ??
                                'No email',
                          ),
                          SizedBox(height: 12.h),
                          _buildInfoRow(
                            Icons.access_time_rounded,
                            'Member since ${_formatDate(Supabase.instance.client.auth.currentUser?.createdAt)}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16.w, color: Colors.grey.shade500),
        SizedBox(width: 12.w),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14.sp,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown';
    }
  }
}
